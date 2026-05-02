#!/system/bin/sh
set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="${RUST_TARGET:-aarch64-linux-android}"
PORT="${PORT:-443}"
BIN="$SCRIPT_DIR/target/$TARGET/debug/gh_proxy-server"
HOSTS_FILE="${HOSTS_FILE:-/system/etc/hosts}"
CA_CERT="$SCRIPT_DIR/keys/ca.pem"

DOMAINS="
github.com
www.github.com
gist.github.com
api.github.com
codeload.github.com
raw.githubusercontent.com
objects.githubusercontent.com
github-releases.githubusercontent.com
"

MARK_BEGIN="# BEGIN 0PROXY"
MARK_END="# END 0PROXY"
HOSTS_BACKUP=""
SERVER_PID=""

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "请使用 root 权限运行此脚本"
        exit 1
    fi
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "缺少命令: $1" >&2
        exit 1
    fi
}

remount_system_rw() {
    mount -o rw,remount /system >/dev/null 2>&1 || true
    mount -o rw,remount / >/dev/null 2>&1 || true
}

remount_system_ro() {
    mount -o ro,remount /system >/dev/null 2>&1 || true
    mount -o ro,remount / >/dev/null 2>&1 || true
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

backup_hosts() {
    if [ ! -f "$HOSTS_FILE" ]; then
        HOSTS_FILE="/etc/hosts"
    fi

    if [ ! -f "$HOSTS_FILE" ]; then
        echo "未找到 hosts 文件" >&2
        exit 1
    fi

    HOSTS_BACKUP="$SCRIPT_DIR/.hosts.0proxy.bak"
    cp "$HOSTS_FILE" "$HOSTS_BACKUP"
}

apply_hosts() {
    TMP_HOSTS="$SCRIPT_DIR/.hosts.0proxy.tmp"

    sed "/$MARK_BEGIN/,/$MARK_END/d" "$HOSTS_FILE" > "$TMP_HOSTS"
    {
        echo "$MARK_BEGIN"
        for domain in $DOMAINS; do
            echo "127.0.0.1 $domain"
        done
        echo "$MARK_END"
    } >> "$TMP_HOSTS"

    remount_system_rw
    if ! cp "$TMP_HOSTS" "$HOSTS_FILE" 2>/dev/null; then
        rm -f "$TMP_HOSTS"
        echo "无法写入 $HOSTS_FILE，请确认 /system 可写或指定 HOSTS_FILE" >&2
        exit 1
    fi

    rm -f "$TMP_HOSTS"
}

restore_hosts() {
    if [ -n "$HOSTS_BACKUP" ] && [ -f "$HOSTS_BACKUP" ]; then
        remount_system_rw
        cp "$HOSTS_BACKUP" "$HOSTS_FILE" 2>/dev/null || true
        rm -f "$HOSTS_BACKUP"
    fi
    remount_system_ro
}

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    restore_hosts
}

need_root
need_cmd sed
ensure_binary
install_android_ca
configure_git
backup_hosts
apply_hosts

trap cleanup EXIT INT TERM

echo "=== 0proxy GitHub 透明代理 ==="
echo "监听端口: $PORT"
echo "hosts 文件: $HOSTS_FILE"
echo "代理域名:"
for domain in $DOMAINS; do
    echo "  $domain -> 127.0.0.1"
done
echo ""
echo "浏览器访问 https://github.com 和 HTTPS git clone 会进入本地代理"
echo "按 Ctrl-C 停止并恢复 hosts"
echo ""

"$BIN" --port "$PORT" &
SERVER_PID="$!"
wait "$SERVER_PID"
