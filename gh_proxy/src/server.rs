use std::{fmt, io::IsTerminal};

use chrono::Local;
use mimalloc::MiMalloc;
use obfstr::obfbytes;
use salvo::prelude::*;
use tracing_subscriber::{
    EnvFilter,
    fmt::{format::Writer, time::FormatTime},
};

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

struct LoggerFormatter;

impl FormatTime for LoggerFormatter {
    fn format_time(&self, w: &mut Writer<'_>) -> fmt::Result {
        write!(w, "{}", Local::now().format("%Y-%m-%d %H:%M:%S"))
    }
}

#[handler]
async fn redirect_to_gh_proxy(req: &mut Request, res: &mut Response) {
    info!("redirect: {}", req.uri());
    res.render(Redirect::found(format!(
        "https://gh-proxy.com/{}",
        req.uri()
    )));
}

pub async fn run_server(port: u16) -> anyhow::Result<()> {
    // 初始化日志
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("debug"));

    let is_terminal = std::io::stdout().is_terminal();

    tracing_subscriber::fmt()
        .with_env_filter(env_filter)
        .with_timer(LoggerFormatter)
        .with_ansi(is_terminal)
        .init();

    // 加载 TLS 证书
    let private_key = obfbytes!(include_bytes!("../../../keys/private_key.pem"));
    let public_key = obfbytes!(include_bytes!("../../../keys/cert.pem"));

    let tls_config = RustlsConfig::new(Keycert::new().cert(public_key).key(private_key));

    // 创建路由
    let router = Router::new()
        .host("github.com")
        .push(
            Router::with_path("/{user}/{repo}/releases/download/{**rest}")
                .goal(redirect_to_gh_proxy),
        )
        .push(Router::with_path("{**rest}").goal(Proxy::use_hyper_client("https://lgithub.xyz")));

    // 启动服务器
    let acceptor = TcpListener::new(format!("0.0.0.0:{}", port))
        .rustls(tls_config)
        .bind()
        .await;

    info!("Server listening on 0.0.0.0:{}", port);

    Server::new(acceptor).serve(router).await;

    Ok(())
}
