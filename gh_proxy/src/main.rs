use std::thread;

use aya::programs::{SchedClassifier, TcAttachType, tc};
use clap::Parser;
use log::{error, info};
use tokio::signal;

use gh_proxy::server;

#[derive(Debug, Parser)]
struct Opt {
    /// Network interface to attach to
    #[clap(short, long, default_value = "wlan0")]
    iface: String,

    /// Server port
    #[clap(short, long, default_value = "443")]
    port: u16,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let opt = Opt::parse();
    env_logger::init();

    info!("=== GitHub Proxy eBPF ===");
    info!("Network interface: {}", opt.iface);
    info!("Server port: {}", opt.port);
    info!("");

    // 启动 salvo 服务器线程
    let server_port = opt.port;
    let _server_handle = thread::spawn(move || {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            if let Err(e) = server::run_server(server_port).await {
                error!("Server error: {}", e);
            }
        });
    });

    // 等待服务器启动
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

    // 启动 eBPF 程序
    info!("Loading eBPF TC program...");

    // 加载 eBPF 程序
    let mut ebpf = aya::Ebpf::load(aya::include_bytes_aligned!(concat!(
        env!("OUT_DIR"),
        "/gh_proxy"
    )))?;

    // 添加 clsact qdisc（如果不存在）
    info!("Adding clsact qdisc to {}", opt.iface);
    let _ = tc::qdisc_add_clsact(&opt.iface);

    // 加载并附加出站 TC 程序
    let egress_prog: &mut SchedClassifier =
        ebpf.program_mut("gh_proxy_egress").unwrap().try_into()?;
    egress_prog.load()?;
    egress_prog.attach(&opt.iface, TcAttachType::Egress)?;
    info!("Attached egress TC program to {}", opt.iface);

    // 加载并附加入站 TC 程序
    let ingress_prog: &mut SchedClassifier =
        ebpf.program_mut("gh_proxy_ingress").unwrap().try_into()?;
    ingress_prog.load()?;
    ingress_prog.attach(&opt.iface, TcAttachType::Ingress)?;
    info!("Attached ingress TC program to {}", opt.iface);

    info!("");
    info!("=== 系统就绪 ===");
    info!(
        "eBPF TC 程序已加载，GitHub 流量将被重定向到 127.0.0.1:{}",
        opt.port
    );
    info!("代理服务器正在监听端口 {}", opt.port);
    info!("按 Ctrl-C 退出...");
    info!("");

    // 等待退出信号
    signal::ctrl_c().await?;

    info!("Shutting down...");

    // 清理 TC 规则
    let _ = tc::qdisc_detach_program(&opt.iface, TcAttachType::Egress, "gh_proxy_egress");
    let _ = tc::qdisc_detach_program(&opt.iface, TcAttachType::Ingress, "gh_proxy_ingress");

    Ok(())
}
