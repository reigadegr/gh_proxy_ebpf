#!/bin/bash
# start.sh - GitHub eBPF 透明代理一键启动
set -e

INTERFACE="${1:-wlan0}"
PORT="${2:-443}"
BIN="./target/aarch64-linux-android/debug/gh_proxy"
LOG_FILE="./gh_proxy.log"

# 1. 停止旧实例
echo "[1/4] 停止旧进程..."
pkill -f "$BIN" 2>/dev/null || true
sleep 1

# 2. 清理可能残留的 clsact（关键！）
echo "[2/4] 清理旧 clsact qdisc..."
tc qdisc del dev "$INTERFACE" clsact 2>/dev/null || true
tc qdisc del dev lo clsact 2>/dev/null || true

# 4. 启动代理（前台运行，日志输出到文件）
echo "[4/4] 启动代理..."
killall -9 gh_proxy || true
RUST_LOG=debug "$BIN" -i "$INTERFACE" -p "$PORT" &
PID=$!
echo "gh_proxy 已启动 (PID: $PID)，日志: $LOG_FILE"

# 等待初始化
sleep 2

# 检查端口监听
if ss -tlnp | grep -q ":$PORT "; then
    echo "✅ 代理端口 $PORT 已监听"
else
    echo "❌ 端口未监听，请查看日志: tail -f $LOG_FILE"
    exit 1
fi

# 检查 eBPF filter 是否成功挂载
if tc filter show dev "$INTERFACE" egress 2>/dev/null | grep -q "gh_proxy_egress"; then
    echo "✅ eBPF 程序已挂载到 $INTERFACE"
else
    echo "⚠️  eBPF 未挂载，但可能是 aya 内部处理，稍后测试"
fi

echo "============================================="
echo "代理就绪！测试命令："
echo "curl -4 -v https://github.com/ 2>&1 | head"
echo "查看日志：tail -f $LOG_FILE"
echo "停止代理：pkill -9 gh_proxy"
