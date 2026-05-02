use std::thread;

use aya::programs::{SchedClassifier, TcAttachType, tc};
use chrono::Local;
use clap::Parser;
use log::{error, info};
use std::{fmt, io::IsTerminal};
use tokio::signal;
use tracing_subscriber::{
    EnvFilter,
    fmt::{format::Writer, time::FormatTime},
};

use gh_proxy::server;

struct LoggerFormatter;

impl FormatTime for LoggerFormatter {
    fn format_time(&self, w: &mut Writer<'_>) -> fmt::Result {
        write!(w, "{}", Local::now().format("%Y-%m-%d %H:%M:%S"))
    }
}

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
    // 初始化日志
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("debug"));

    let is_terminal = std::io::stdout().is_terminal();

    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_timer(LoggerFormatter)
        .with_ansi(is_terminal)
        .init();

    info!("=== GitHub Proxy eBPF ===");
    info!("Network interface: {}", opt.iface);
    info!("Server port: {}", opt.port);
    info!("");

    // 启动 salvo 服务器线程
    let server_port = opt.port;
    let _server_handle = thread::spawn(move || {
        // SAFETY: tokio runtime creation should not fail in normal circumstances
        #[allow(clippy::expect_used)]
        let rt = tokio::runtime::Runtime::new().expect("Failed to create tokio runtime");
        rt.block_on(async {
            if let Err(e) = server::run_server(server_port).await {
                error!("Server error: {e}");
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

    match tc::qdisc_add_clsact(&opt.iface) {
        Ok(()) => info!("clsact added to {}", opt.iface),
        Err(e) => error!("Failed to add clsact to {}: {e}", opt.iface),
    }
    match tc::qdisc_add_clsact("lo") {
        Ok(()) => info!("clsact added to lo"),
        Err(e) => error!("Failed to add clsact to lo: {e}", opt.iface),
    }

    // 加载并附加出站 TC 程序到 wlan0
    #[allow(clippy::expect_used)]
    let egress_prog: &mut SchedClassifier = ebpf
        .program_mut("gh_proxy_egress")
        .expect("gh_proxy_egress program not found")
        .try_into()?;
    egress_prog.load()?;
    egress_prog.attach(&opt.iface, TcAttachType::Egress)?;
    info!("Attached egress TC program to {}", opt.iface);

    // 加载并附加 lo 出站 TC 程序（用于翻译响应源地址）
    #[allow(clippy::expect_used)]
    let lo_egress_prog: &mut SchedClassifier = ebpf
        .program_mut("gh_proxy_lo_egress")
        .expect("gh_proxy_lo_egress program not found")
        .try_into()?;
    lo_egress_prog.load()?;
    lo_egress_prog.attach("lo", TcAttachType::Egress)?;
    info!("Attached lo egress TC program to lo");

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
    let _ = tc::qdisc_detach_program("lo", TcAttachType::Egress, "gh_proxy_lo_egress");

    Ok(())
}
