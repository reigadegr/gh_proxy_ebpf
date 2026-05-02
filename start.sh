#!/bin/bash
set -ex
INTERFACE="${1:-wlan0}"
PORT="${2:-443}"
BIN="./target/aarch64-linux-android/debug/gh_proxy"

# 清理旧 clsact
echo "清理旧 clsact..."
tc qdisc del dev "$INTERFACE" clsact 2>/dev/null || true
tc qdisc del dev lo clsact 2>/dev/null || true

echo "启动代理..."
killall -9 gh_proxy 2>/dev/null || true
RUST_LOG=debug $BIN -i "$INTERFACE" -p "$PORT"
