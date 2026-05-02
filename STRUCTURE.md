# GitHub Proxy eBPF 项目结构

## 目录结构

```
/data/data/com.termux/files/home/0proxy/
├── Cargo.toml                      # 工作空间配置
├── start.sh                        # 启动脚本
├── README.md                       # 项目说明
├── keys/                           # TLS 证书（已存在）
│   ├── private_key.pem
│   └── cert.pem
│
├── gh_proxy/                       # 主程序
│   ├── Cargo.toml                  # 主程序依赖
│   └── src/
│       ├── lib.rs                  # 库模块（导出 server）
│       ├── main.rs                 # 主入口（多线程启动 eBPF + 服务器）
│       ├── server.rs               # Salvo 代理服务器模块
│       └── server_bin.rs           # 独立服务器二进制
│
├── gh_proxy-ebpf/                  # eBPF TC 程序
│   ├── Cargo.toml                  # eBPF 依赖
│   ├── build.rs                    # 构建脚本
│   └── src/
│       └── main.rs                 # TC eBPF 程序（修改数据包目标地址）
│
└── gh_proxy-common/                # 共享类型定义
    ├── Cargo.toml                  # 共享依赖
    └── src/
        └── lib.rs                  # 共享类型
```

## 二进制文件

编译后会生成两个二进制文件：

1. **gh_proxy** - 主程序（多线程：eBPF + 服务器）
2. **gh_proxy-server** - 独立服务器（仅 Salvo）

## 使用方法

### 方式 1: 使用启动脚本（推荐）

```bash
cd /data/data/com.termux/files/home/0proxy
sudo ./start.sh
```

### 方式 2: 手动编译和运行

```bash
cd /data/data/com.termux/files/home/0proxy

# 编译
cargo build --release -p gh_proxy

# 运行主程序（多线程）
sudo ./target/release/gh_proxy --iface wlan0 --port 443

# 或者只运行服务器
sudo ./target/release/gh_proxy-server --port 443
```

### 方式 3: 使用 Cargo 运行

```bash
cd /data/data/com.termux/files/home/0proxy

# 运行主程序
sudo cargo run --release -p gh_proxy -- --iface wlan0 --port 443

# 或者只运行服务器
sudo cargo run --release -p gh_proxy --bin gh_proxy-server -- --port 443
```

## 工作原理

### 多线程架构

- **线程 1**: eBPF TC 程序拦截 GitHub 流量，修改目标地址为 127.0.0.1:443
- **线程 2**: Salvo 服务器监听 443 端口，处理 TLS 握手并转发请求

### 流量流程

```
浏览器 -> github.com
    ↓
eBPF TC 拦截
    ↓
修改目标地址为 127.0.0.1:443
    ↓
Salvo 服务器接收
    ↓
转发到 gh-proxy.com 或 lgithub.xyz
    ↓
返回响应给浏览器
```

## 配置说明

### 命令行参数

```
gh_proxy [OPTIONS]

OPTIONS:
  -i, --iface <IFACE>    网络接口 [default: wlan0]
  -p, --port <PORT>      服务器端口 [default: 443]
  -h, --help             显示帮助
```

### GitHub IP 段

在 `gh_proxy-ebpf/src/main.rs` 中修改 `GITHUB_IPS` 常量。

### 网络接口

根据你的设备选择正确的接口：
- WiFi: `wlan0`
- 移动数据: `rmnet0` 或 `rmnet_data0`
- 以太网: `eth0`

## 故障排除

### 编译失败

确保安装了必要的工具链：
```bash
rustup toolchain install nightly
rustup default nightly
cargo install bpf-linker
```

### TC 操作失败

清理旧的 TC 规则：
```bash
sudo tc qdisc del dev wlan0 clsact
```

### 权限问题

所有操作都需要 root 权限。

## 测试

```bash
# 测试访问 GitHub
curl -I https://github.com

# 在浏览器中访问
# https://github.com
```
