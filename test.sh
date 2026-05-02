#!/system/bin/sh

# 测试脚本
set -e

echo "=== 测试 GitHub Proxy eBPF 项目 ==="
echo ""

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 检查目录结构
echo "检查项目结构..."
if [ -d "gh_proxy" ] && [ -d "gh_proxy-ebpf" ] && [ -d "gh_proxy-common" ]; then
    echo "✓ 项目目录结构正确"
else
    echo "✗ 项目目录结构不正确"
    exit 1
fi

# 检查必要文件
echo "检查必要文件..."
for file in "Cargo.toml" "gh_proxy/Cargo.toml" "gh_proxy-ebpf/Cargo.toml" "gh_proxy-common/Cargo.toml"; do
    if [ -f "$file" ]; then
        echo "✓ $file"
    else
        echo "✗ $file 缺失"
        exit 1
    fi
done

# 检查源文件
echo "检查源文件..."
for file in "gh_proxy/src/main.rs" "gh_proxy/src/server.rs" "gh_proxy/src/lib.rs" "gh_proxy-ebpf/src/main.rs"; do
    if [ -f "$file" ]; then
        echo "✓ $file"
    else
        echo "✗ $file 缺失"
        exit 1
    fi
done

echo ""
echo "=== 项目结构检查通过 ==="
echo ""
echo "可以使用以下命令编译和运行："
echo ""
echo "  cd $SCRIPT_DIR"
echo "  sudo ./start.sh"
echo ""
