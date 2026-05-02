#!/system/bin/sh

# GitHub 代理 eBPF 启动脚本
# 多线程启动：eBPF 拦截 + Salvo 服务器
# 需要 root 权限运行

set -e

# 检查是否 root
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 自动检测网络接口
detect_interface() {
    for iface in wlan0 rmnet0 rmnet_data0 pdp_ip0 eth0; do
        if ip link show "$iface" &>/dev/null; then
            echo "$iface"
            return 0
        fi
    done
    ip link show | grep -E "^[0-9]+" | awk '{print $2}' | sed 's/://' | head -1
}

IFACE="${1:-$(detect_interface)}"
PORT="${2:-443}"

# 清理函数
cleanup() {
    echo ""
    echo "清理 TC 规则..."
    tc qdisc del dev "$IFACE" clsact 2>/dev/null || true
    echo "清理完成"
}

trap cleanup EXIT

echo "=== GitHub Proxy eBPF ==="
echo ""
echo "网络接口: $IFACE"
echo "服务器端口: $PORT"
echo ""

# 编译项目
echo "编译项目..."
cd "$(dirname "$0")"
cargo build --release -p gh_proxy

if [ ! -f "./target/release/gh_proxy" ]; then
    echo "错误: 编译失败"
    exit 1
fi

echo "编译完成"
echo ""
echo "启动 GitHub 代理系统..."
echo "按 Ctrl-C 退出"
echo ""

# 启动主程序（多线程）
./target/release/gh_proxy --iface "$IFACE" --port "$PORT"
