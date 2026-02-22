#!/bin/bash
# 校园网自动登录 - Linux 一键部署 (零依赖)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo "   校园网自动登录 Linux 一键部署"
echo "   (零依赖 bash+curl+openssl 版)"
echo "========================================"
echo

# 检测依赖
for cmd in curl openssl; do
    if ! command -v $cmd &>/dev/null; then
        echo "[错误] 未检测到 $cmd，请先安装"
        exit 1
    fi
done

# 输入账号密码
echo "[1/4] 请输入校园网账号信息:"
read -rp "  学号: " SRUN_USER
read -rsp "  密码: " SRUN_PASS
echo
echo "  默认服务器: http://192.168.75.252"
echo "  如果你的校区不同，请输入正确的服务器地址"
read -rp "  服务器地址(直接回车使用默认): " SRUN_SERVER
: "${SRUN_SERVER:=http://192.168.75.252}"

# 生成配置文件
echo
echo "[2/4] 生成配置文件..."
cat > "$SCRIPT_DIR/config.ini" <<EOF
[srun]
username = $SRUN_USER
password = $SRUN_PASS
server = $SRUN_SERVER
ac_id = 1
EOF
chmod 600 "$SCRIPT_DIR/config.ini"
echo "      config.ini 已生成"

# 创建 systemd 用户服务
echo
echo "[3/4] 设置开机自启..."
chmod +x "$SCRIPT_DIR/srun_login.sh"
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/srun-login.service <<EOF
[Unit]
Description=Srun Campus Network Auto Login
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=$SCRIPT_DIR/srun_login.sh --keepalive
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable srun-login.service
systemctl --user start srun-login.service
loginctl enable-linger "$(whoami)" 2>/dev/null || true
echo "      systemd 服务已启用"

# 测试登录
echo
echo "----------------------------------------"
echo "[4/4] 测试登录..."
echo "----------------------------------------"
bash "$SCRIPT_DIR/srun_login.sh"

# 验证联网（用HTTP检测，校园网可能屏蔽ping）
echo
echo "验证网络连通性（等待网络就绪）..."
sleep 3
if curl -s -o /dev/null -w '%{http_code}' --max-time 10 'https://www.baidu.com' | grep -q '200'; then
    echo "[成功] 网络已连通，可正常上网！"
else
    echo "[失败] 无法访问外网，请检查账号密码是否正确"
fi

echo
echo "========================================"
echo "  部署完成！已设置开机自动登录"
echo "========================================"
echo
echo "  查看状态: systemctl --user status srun-login"
echo "  查看日志: journalctl --user -u srun-login -f"
echo "  停止服务: systemctl --user stop srun-login"
echo "  卸载自启: systemctl --user disable --now srun-login"
