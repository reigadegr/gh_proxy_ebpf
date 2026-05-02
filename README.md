# GitHub Proxy eBPF

使用 eBPF 技术在国内无需 VPN 即可流畅访问 GitHub。

## 项目特点

- **纯 eBPF 方案**：无需 iptables，直接使用 eBPF TC 修改数据包
- **多线程架构**：eBPF 拦截 + Salvo 服务器并行运行

## 项目结构

```
0proxy/
├── Cargo.toml                      # 工作空间配置
├── start.sh                        # 启动脚本
├── test.sh                         # 测试脚本
├── README.md                       # 项目说明
├── keys/                           # TLS 证书
│   ├── private_key.pem
│   └── cert.pem
│
├── gh_proxy/                       # 主程序
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs                  # 库模块（导出 server）
│       ├── main.rs                 # 主入口（多线程启动 eBPF + 服务器）
│       └── server.rs               # Salvo 代理服务器模块
│
├── gh_proxy-ebpf/                  # eBPF TC 程序
│   ├── Cargo.toml
│   ├── build.rs                    # 构建脚本
│   └── src/
│       └── main.rs                 # TC eBPF 程序
│
└── gh_proxy-common/                # 共享类型定义
    ├── Cargo.toml
    └── src/
        └── lib.rs
```

## 快速开始

### 前提条件

1. Root 权限的 Android 设备
2. Rust 工具链（nightly）
3. eBPF 相关组件

### 安装依赖

```bash
# 安装 Rust nightly
rustup toolchain install nightly
rustup default nightly

# 安装 eBPF 工具
cargo install bpf-linker
```

### 编译和运行

```bash
cd /data/data/com.termux/files/home/0proxy

# 方式 1: 使用启动脚本（推荐）
sudo ./start.sh

# 方式 2: 手动编译和运行
cargo build --release -p gh_proxy
sudo ./target/release/gh_proxy --iface wlan0 --port 443
```

### 测试

```bash
# 测试访问 GitHub
curl -I https://github.com

# 在浏览器中访问
# https://github.com
```

## 工作原理

### 多线程架构

- **线程 1**: eBPF TC 程序拦截 GitHub 流量，修改目标地址为 127.0.0.1:443
- **线程 2**: Salvo 服务器监听 443 端口，处理 TLS 握手并转发请求

### 流量流程

```
浏览器 -> github.com
    ↓
eBPF TC 拦截（出站流量）
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

在 `gh_proxy-ebpf/src/main.rs` 中修改 `GITHUB_IPS` 常量：

```rust
const GITHUB_IPS: [(u32, u32); 3] = [
    (0x141C7000, 0xFFFFFF00), // 20.28.112.0/24
    (0x8C520000, 0xFFFFF000), // 140.82.112.0/20
    (0xC01EFC00, 0xFFFFFC00), // 192.30.252.0/22
];
```

### 网络接口

根据你的设备选择正确的接口：
- WiFi: `wlan0`
- 移动数据: `rmnet0` 或 `rmnet_data0`
- 以太网: `eth0`

## 关于 HTTPS 端口

**是的，仍然需要监听 HTTPS 端口**，原因如下：

1. **eBPF 只负责重定向**：TC 程序将流量的目标地址修改为本地端口
2. **TLS 握手需要本地处理**：客户端期望连接 `github.com`，需要本地服务器提供相应的证书
3. **代理逻辑在用户空间**：转发到 `gh-proxy.com` 等逻辑在 Rust 服务器中实现

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

所有操作都需要 root 权限：
```bash
sudo ./start.sh
```

### 端口被占用

检查端口是否被占用：
```bash
sudo ss -tln | grep :443
```

## 许可证

MIT License
