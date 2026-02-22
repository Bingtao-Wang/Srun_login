#!/bin/bash
# 山东大学-深澜(Srun)校园网自动登录 (bash+curl+openssl, 零依赖)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.ini"
ENC_VER="srun_bx1"; N="200"; TYPE="1"
STD_ALPHA='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
SRUN_ALPHA='LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA='

# ---- Config ----
if [ ! -f "$CONFIG_FILE" ]; then echo "错误: 未找到 config.ini，请先运行一键部署"; exit 1; fi
USERNAME=$(sed -n 's/^username\s*=\s*//p' "$CONFIG_FILE" | tr -d '[:space:]')
PASSWORD=$(sed -n 's/^password\s*=\s*//p' "$CONFIG_FILE" | tr -d '[:space:]')
AC_ID=$(sed -n 's/^ac_id\s*=\s*//p' "$CONFIG_FILE" | tr -d '[:space:]')
SERVER=$(sed -n 's/^server\s*=\s*//p' "$CONFIG_FILE" | tr -d '[:space:]')
: "${AC_ID:=1}" "${SERVER:=http://192.168.75.252}"

# ---- Encode helpers ----
# sencode: string -> uint32 array V[], with optional length append
sencode() {
    local msg="$1" append_len=$2
    local l=${#msg} i j c val
    V=()
    for ((i=0; i<l; i+=4)); do
        val=0
        for ((j=0; j<4; j++)); do
            if ((i+j < l)); then
                c=$(printf '%d' "'${msg:i+j:1}")
                val=$(( val | (c << (j*8)) ))
            fi
        done
        V+=( $((val & 0xFFFFFFFF)) )
    done
    if ((append_len)); then V+=($l); fi
}

# lencode: uint32 array V[] -> raw bytes (hex string in LENC_HEX)
lencode() {
    LENC_HEX=""
    local val
    for val in "${V[@]}"; do
        LENC_HEX+=$(printf '%02x%02x%02x%02x' $((val & 0xFF)) $(((val>>8)&0xFF)) $(((val>>16)&0xFF)) $(((val>>24)&0xFF)))
    done
}

# ---- XXTEA ----
xxtea_encode() {
    local msg="$1" key="$2"
    if [ -z "$msg" ]; then XXTEA_HEX=""; return; fi
    sencode "$msg" 1; local -a v=("${V[@]}")
    sencode "$key" 0; local -a k=("${V[@]}")
    while ((${#k[@]} < 4)); do k+=(0); done

    local n=$(( ${#v[@]} - 1 )) z=${v[$((${#v[@]}-1))]}
    local q=$(( 6 + 52 / (n + 1) )) d=0 e p y m

    while ((q > 0)); do
        d=$(( (d + 0x9E3779B9) & 0xFFFFFFFF ))
        e=$(( (d >> 2) & 3 ))
        for ((p=0; p<n; p++)); do
            y=${v[$((p+1))]}
            m=$(( ((z >> 5) ^ ((y << 2) & 0xFFFFFFFF)) ))
            m=$(( m + (((y >> 3) ^ ((z << 4) & 0xFFFFFFFF)) ^ (d ^ y)) ))
            m=$(( m + (k[((p & 3) ^ e)] ^ z) ))
            v[$p]=$(( (v[p] + m) & 0xFFFFFFFF ))
            z=${v[$p]}
        done
        y=${v[0]}
        m=$(( ((z >> 5) ^ ((y << 2) & 0xFFFFFFFF)) ))
        m=$(( m + (((y >> 3) ^ ((z << 4) & 0xFFFFFFFF)) ^ (d ^ y)) ))
        m=$(( m + (k[((n & 3) ^ e)] ^ z) ))
        v[$n]=$(( (v[n] + m) & 0xFFFFFFFF ))
        z=${v[$n]}
        ((q--))
    done
    V=("${v[@]}"); lencode
    XXTEA_HEX="$LENC_HEX"
}

# ---- Custom Base64 ----
srun_base64() {
    local hex="$1"
    local b64=$(echo -n "$hex" | xxd -r -p | base64 | tr -d '\n')
    SRUN_B64=$(echo -n "$b64" | tr "$STD_ALPHA" "$SRUN_ALPHA")
}

# ---- Crypto ----
hmac_md5() {
    local key="$1" msg="$2"
    HMAC_MD5=$(echo -n "$msg" | openssl dgst -md5 -hmac "$key" | sed 's/.*= //')
}

sha1_hex() {
    local s="$1"
    SHA1=$(echo -n "$s" | openssl dgst -sha1 | sed 's/.*= //')
}

# ---- JSONP parse ----
parse_jsonp_field() {
    local text="$1" field="$2"
    echo "$text" | sed 's/.*srun_callback(\(.*\))/\1/' | grep -oP "\"$field\"\s*:\s*\"?\K[^,\"}\)]+" | head -1
}

# ---- URL encode ----
urlencode() {
    local s="$1"
    python3 -c "import urllib.parse; print(urllib.parse.quote('$s'))" 2>/dev/null \
    || printf '%s' "$s" | curl -Gso /dev/null -w '%{url_effective}' --data-urlencode @- '' | cut -c3-
}

# ---- Login ----
do_login() {
    local ts=$(($(date +%s%N)/1000000))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始登录..."

    local resp=$(curl -s --max-time 10 "$SERVER/cgi-bin/get_challenge?callback=srun_callback&username=$USERNAME&ip=&_=$ts")
    local token=$(parse_jsonp_field "$resp" "challenge")
    local ip=$(parse_jsonp_field "$resp" "client_ip")
    echo "  token 获取成功, IP: $ip"

    local info_json="{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\",\"ip\":\"$ip\",\"acid\":\"$AC_ID\",\"enc_ver\":\"$ENC_VER\"}"
    xxtea_encode "$info_json" "$token"
    srun_base64 "$XXTEA_HEX"
    local info="{SRBX1}$SRUN_B64"

    hmac_md5 "$token" "$PASSWORD"
    local hmd5="$HMAC_MD5"
    local password_enc="{MD5}$hmd5"

    sha1_hex "${token}${USERNAME}${token}${hmd5}${token}${AC_ID}${token}${ip}${token}${N}${token}${TYPE}${token}${info}"
    local chksum="$SHA1"

    local ts2=$(($(date +%s%N)/1000000))
    local enc_pass enc_info
    enc_pass=$(printf '%s' "$password_enc" | jq -sRr @uri 2>/dev/null || urlencode "$password_enc")
    enc_info=$(printf '%s' "$info" | jq -sRr @uri 2>/dev/null || urlencode "$info")

    local resp2=$(curl -s --max-time 10 "$SERVER/cgi-bin/srun_portal?callback=srun_callback&action=login&username=$USERNAME&password=$enc_pass&os=Linux&name=Linux&double_stack=0&chksum=$chksum&info=$enc_info&ac_id=$AC_ID&ip=$ip&n=$N&type=$TYPE&_=$ts2")
    local err=$(parse_jsonp_field "$resp2" "error")

    if [ "$err" = "ok" ] || [ "$err" = "up_pwd_alert" ]; then
        echo "  登录成功! 用户: $USERNAME, IP: $ip"; return 0
    else
        local errmsg=$(parse_jsonp_field "$resp2" "error_msg")
        echo "  登录失败: ${errmsg:-$err}"; return 1
    fi
}

check_network() {
    curl -s --max-time 5 -o /dev/null -w '%{http_code}' 'https://www.baidu.com' | grep -q '200'
}

# ---- Main ----
MODE="once"
if [ "${1:-}" = "--keepalive" ] || [ "${1:-}" = "-keepalive" ]; then MODE="keepalive"; fi
if [ "$MODE" = "keepalive" ]; then echo "等待网络接口就绪..."; sleep 10; fi

for i in $(seq 1 5); do
    if do_login; then break; fi
    echo "  第${i}次尝试失败"; sleep 5
done

if [ "$MODE" = "keepalive" ]; then
    echo "进入保活模式，每5分钟检测一次..."
    while true; do
        sleep 300
        if ! check_network; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 网络断开，重新登录..."
            do_login || echo "  重连失败"
        fi
    done
fi
