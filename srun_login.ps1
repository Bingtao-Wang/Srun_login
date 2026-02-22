param([switch]$keepalive)
$ErrorActionPreference = 'Stop'
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$CONFIG_FILE = Join-Path $SCRIPT_DIR 'config.ini'
$ENC_VER = 'srun_bx1'
$N = '200'; $TYPE = '1'
$STD_ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
$SRUN_ALPHA = 'LVoJPiCN2R8G90yg+hmFHuacZ1OWMnrsSTXkYpUq/3dlbfKwv6xztjI7DeBE45QA='

# ---- Config ----
if (!(Test-Path $CONFIG_FILE)) { Write-Host '错误: 未找到 config.ini，请先运行一键部署'; exit 1 }
$cfg = @{}
Get-Content $CONFIG_FILE -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^\s*(\w+)\s*=\s*(.+?)\s*$') { $cfg[$Matches[1]] = $Matches[2] }
}
$USERNAME = $cfg['username']; $PASSWORD = $cfg['password']
$AC_ID = if ($cfg['ac_id']) { $cfg['ac_id'] } else { '1' }
$SERVER = if ($cfg['server']) { $cfg['server'] } else { 'http://192.168.75.252' }

# ---- Encode helpers ----
function ordat($s, $i) { if ($i -lt $s.Length) { [int][char]$s[$i] } else { 0 } }

function sencode($msg, [bool]$appendLen) {
    $l = $msg.Length; $v = [System.Collections.Generic.List[long]]::new()
    for ($i = 0; $i -lt $l; $i += 4) {
        $val = [long](ordat $msg $i) -bor ([long](ordat $msg ($i+1)) -shl 8) -bor ([long](ordat $msg ($i+2)) -shl 16) -bor ([long](ordat $msg ($i+3)) -shl 24)
        $v.Add($val)
    }
    if ($appendLen) { $v.Add([long]$l) }
    return $v
}

function lencode($v) {
    $sb = [System.Text.StringBuilder]::new()
    foreach ($val in $v) {
        [void]$sb.Append([char]($val -band 0xFF))
        [void]$sb.Append([char](($val -shr 8) -band 0xFF))
        [void]$sb.Append([char](($val -shr 16) -band 0xFF))
        [void]$sb.Append([char](($val -shr 24) -band 0xFF))
    }
    return $sb.ToString()
}

# ---- XXTEA ----
function xxtea_encode($msg, $key) {
    if ($msg -eq '') { return '' }
    $v = sencode $msg $true
    $k = sencode $key $false
    while ($k.Count -lt 4) { $k.Add(0L) }
    $n = $v.Count - 1; $z = $v[$n]
    $q = 6 + [math]::Floor(52 / ($n + 1)); $d = 0L
    while ($q -gt 0) {
        $d = ($d + 0x9E3779B9L) -band 0xFFFFFFFFL
        $e = ($d -shr 2) -band 3
        for ($p = 0; $p -lt $n; $p++) {
            $y = $v[$p + 1]
            $m = (($z -shr 5) -bxor (($y -shl 2) -band 0xFFFFFFFFL))
            $m = ($m + ((($y -shr 3) -bxor (($z -shl 4) -band 0xFFFFFFFFL)) -bxor ($d -bxor $y)))
            $m = ($m + ($k[($p -band 3) -bxor $e] -bxor $z))
            $v[$p] = ($v[$p] + $m) -band 0xFFFFFFFFL
            $z = $v[$p]
        }
        $y = $v[0]
        $m = (($z -shr 5) -bxor (($y -shl 2) -band 0xFFFFFFFFL))
        $m = ($m + ((($y -shr 3) -bxor (($z -shl 4) -band 0xFFFFFFFFL)) -bxor ($d -bxor $y)))
        $m = ($m + ($k[($n -band 3) -bxor $e] -bxor $z))
        $v[$n] = ($v[$n] + $m) -band 0xFFFFFFFFL
        $z = $v[$n]
        $q--
    }
    return (lencode $v)
}

# ---- Custom Base64 ----
function srun_base64($s) {
    $bytes = [byte[]]($s.ToCharArray() | ForEach-Object { [byte]([int][char]$_ -band 0xFF) })
    $b64 = [Convert]::ToBase64String($bytes)
    $out = [System.Text.StringBuilder]::new($b64.Length)
    foreach ($c in $b64.ToCharArray()) {
        $idx = $STD_ALPHA.IndexOf($c)
        if ($idx -ge 0) { [void]$out.Append($SRUN_ALPHA[$idx]) } else { [void]$out.Append($c) }
    }
    return $out.ToString()
}

# ---- Crypto ----
function hmac_md5($key, $msg) {
    $h = [System.Security.Cryptography.HMACMD5]::new([System.Text.Encoding]::UTF8.GetBytes($key))
    $hash = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($msg))
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

function sha1_hex($s) {
    $h = [System.Security.Cryptography.SHA1]::Create()
    $hash = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($s))
    return ($hash | ForEach-Object { $_.ToString('x2') }) -join ''
}

# ---- JSONP parse ----
function parse_jsonp($text) {
    if ($text -match 'srun_callback\((.+)\)') { return $Matches[1] | ConvertFrom-Json }
    throw "JSONP 解析失败: $text"
}

# ---- Login ----
function Do-Login {
    $ts = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 开始登录..."

    $r = Invoke-WebRequest -Uri "$SERVER/cgi-bin/get_challenge?callback=srun_callback&username=$USERNAME&ip=&_=$ts" -UseBasicParsing -TimeoutSec 10
    $ch = parse_jsonp $r.Content
    $token = $ch.challenge; $ip = $ch.client_ip
    Write-Host "  token 获取成功, IP: $ip"

    $info_json = "{`"username`":`"$USERNAME`",`"password`":`"$PASSWORD`",`"ip`":`"$ip`",`"acid`":`"$AC_ID`",`"enc_ver`":`"$ENC_VER`"}"
    $encrypted = xxtea_encode $info_json $token
    $info = "{SRBX1}" + (srun_base64 $encrypted)

    $hmd5 = hmac_md5 $token $PASSWORD
    $password_enc = "{MD5}" + $hmd5
    $chksum = sha1_hex ($token + $USERNAME + $token + $hmd5 + $token + $AC_ID + $token + $ip + $token + $N + $token + $TYPE + $token + $info)

    $ts2 = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    $qs = "callback=srun_callback&action=login&username=$USERNAME&password=$([uri]::EscapeDataString($password_enc))&os=Windows&name=Windows&double_stack=0&chksum=$chksum&info=$([uri]::EscapeDataString($info))&ac_id=$AC_ID&ip=$ip&n=$N&type=$TYPE&_=$ts2"
    $r2 = Invoke-WebRequest -Uri "$SERVER/cgi-bin/srun_portal?$qs" -UseBasicParsing -TimeoutSec 10
    $result = parse_jsonp $r2.Content

    if ($result.error -in @('ok','up_pwd_alert')) {
        Write-Host "  登录成功! 用户: $USERNAME, IP: $ip"; return $true
    } else {
        $err = if ($result.error_msg) { $result.error_msg } else { $result.error }
        Write-Host "  登录失败: $err"; return $false
    }
}

function Check-Network {
    try { $r = Invoke-WebRequest -Uri 'https://www.baidu.com' -UseBasicParsing -TimeoutSec 5; return $r.StatusCode -eq 200 }
    catch { return $false }
}

# ---- Main ----
if ($keepalive) { Write-Host '等待网络接口就绪...'; Start-Sleep -Seconds 10 }
for ($i = 0; $i -lt 5; $i++) {
    try { if (Do-Login) { break } } catch { Write-Host "  第$($i+1)次尝试异常: $_" }
    Start-Sleep -Seconds 5
}
if ($keepalive) {
    Write-Host '进入保活模式，每5分钟检测一次...'
    while ($true) {
        Start-Sleep -Seconds 300
        if (!(Check-Network)) {
            Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 网络断开，重新登录..."
            try { Do-Login } catch { Write-Host "  重连失败: $_" }
        }
    }
}
