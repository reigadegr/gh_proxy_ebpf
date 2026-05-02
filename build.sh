#!/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$SCRIPT_DIR"

PLATFORM="${ANDROID_PLATFORM:-35}"
ABI="${ANDROID_ABI:-arm64-v8a}"
TARGET="${RUST_TARGET:-aarch64-linux-android}"

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少命令: $1" >&2
        exit 1
    fi
}

need cargo
need rustup
need openssl

if ! cargo +nightly --version >/dev/null 2>&1; then
    echo "缺少 Rust nightly 工具链" >&2
    echo "请先执行: rustup toolchain install nightly" >&2
    exit 1
fi

if ! cargo ndk --version >/dev/null 2>&1; then
    echo "缺少 cargo-ndk" >&2
    echo "请先执行: cargo install cargo-ndk" >&2
    exit 1
fi

if ! rustup target list --installed | grep -qx "$TARGET"; then
    rustup target install "$TARGET"
fi

if [ -z "${ANDROID_NDK_HOME:-}" ] && [ -z "${NDK_HOME:-}" ]; then
    echo "缺少 ANDROID_NDK_HOME 或 NDK_HOME" >&2
    exit 1
fi

if [ ! -f keys/ca.pem ] || [ ! -f keys/private_key.pem ] || [ ! -f keys/cert.pem ]; then
    sh ./gen_cert.sh
fi

cargo +nightly ndk --platform "$PLATFORM" -t "$ABI" build --target "$TARGET"

BIN_DIR="$SCRIPT_DIR/target/$TARGET/debug"

if [ ! -x "$BIN_DIR/gh_proxy" ]; then
    echo "编译完成但未找到预期产物: $BIN_DIR" >&2
    exit 1
fi

echo "编译完成:"
echo "  $BIN_DIR/gh_proxy"
