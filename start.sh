#!/system/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="${RUST_TARGET:-aarch64-linux-android}"
PORT="${PORT:-443}"
BIN="$SCRIPT_DIR/target/$TARGET/debug/gh_proxy"
CA_CERT="$SCRIPT_DIR/keys/ca.pem"
SERVER_PID=""

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行此脚本"
        exit 1
    fi
}

remount_system_rw() {
    mount -o rw,remount /system >/dev/null 2>&1 || true
    mount -o rw,remount / >/dev/null 2>&1 || true
}

ensure_binary() {
    if [ ! -x "$BIN" ]; then
        echo "未找到 Android debug 产物，开始编译..."
        sh "$SCRIPT_DIR/build.sh"
    fi

    if [ ! -x "$BIN" ]; then
        echo "未找到可执行文件: $BIN" >&2
        exit 1
    fi
}

install_android_ca() {
    if [ ! -f "$CA_CERT" ]; then
        echo "缺少 CA 证书: $CA_CERT" >&2
        exit 1
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        echo "跳过 Android CA 安装: 缺少 openssl"
        return 0
    fi

    CERT_DIR="/system/etc/security/cacerts"
    if [ ! -d "$CERT_DIR" ]; then
        echo "跳过 Android CA 安装: 未找到 $CERT_DIR"
        return 0
    fi

    HASH="$(openssl x509 -subject_hash_old -in "$CA_CERT" -noout)"
    DEST="$CERT_DIR/$HASH.0"

    if [ -f "$DEST" ] && cmp -s "$CA_CERT" "$DEST"; then
        return 0
    fi

    remount_system_rw
    if cp "$CA_CERT" "$DEST" 2>/dev/null; then
        chmod 644 "$DEST"
        chown root:root "$DEST" 2>/dev/null || true
        restorecon "$DEST" 2>/dev/null || true
        echo "已安装 Android 系统 CA: $DEST"
    else
        echo "警告: 无法写入 $DEST"
        echo "浏览器如仍提示证书不受信任，请手动信任 $CA_CERT"
    fi
}

configure_git() {
    if ! command -v git >/dev/null 2>&1; then
        return 0
    fi

    git config --global http.https://github.com.sslCAInfo "$CA_CERT"
    git config --global http.https://www.github.com.sslCAInfo "$CA_CERT"
    git config --global http.https://gist.github.com.sslCAInfo "$CA_CERT"
    git config --global http.https://api.github.com.sslCAInfo "$CA_CERT"
    git config --global http.https://codeload.github.com.sslCAInfo "$CA_CERT"
    git config --global url."https://github.com/".insteadOf "git@github.com:"
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
}

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

need_root
ensure_binary
install_android_ca
configure_git
trap cleanup EXIT INT TERM

IFACE="${IFACE:-wlan0}"

echo "=== 0proxy ==="
echo "网络接口: $IFACE"
echo "监听端口: $PORT"
echo ""
echo "eBPF 已强制拦截 GitHub 流量，无需 hosts 配置"
echo "按 Ctrl-C 退出"
echo ""
killall -9 gh_proxy || true
"$BIN" --iface "$IFACE" --port "$PORT" &
wait "$SERVER_PID"
