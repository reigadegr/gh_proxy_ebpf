use log::info;
use mimalloc::MiMalloc;
use salvo::conn::rustls::{Keycert, RustlsConfig};
use salvo::prelude::*;
use salvo::proxy::Proxy;

#[global_allocator]
static GLOBAL: MiMalloc = MiMalloc;

#[handler]
async fn redirect_to_gh_proxy(req: &mut Request, res: &mut Response) {
    info!("redirect: {}", req.uri());
    res.render(Redirect::found(format!(
        "https://gh-proxy.com/{}",
        req.uri()
    )));
}

#[handler]
async fn proxy_with_log(
    req: &mut Request,
    depot: &mut Depot,
    res: &mut Response,
    ctrl: &mut FlowCtrl,
) {
    info!("proxy: {} {}", req.method(), req.uri());
    Proxy::use_hyper_client("https://lgithub.xyz")
        .handle(req, depot, res, ctrl)
        .await;
}

pub async fn run_server(port: u16) -> anyhow::Result<()> {
    // 加载 TLS 证书
    let private_key = include_bytes!("../../keys/private_key.pem");
    let public_key = include_bytes!("../../keys/cert.pem");

    let tls_config = RustlsConfig::new(Keycert::new().cert(public_key).key(private_key));

    // 创建路由
    let router = Router::new()
        .push(
            Router::with_path("/{user}/{repo}/releases/download/{**rest}")
                .goal(redirect_to_gh_proxy),
        )
        .push(Router::with_path("{**rest}").goal(proxy_with_log));

    // 启动服务器
    let acceptor = TcpListener::new(format!("0.0.0.0:{port}"))
        .rustls(tls_config)
        .bind()
        .await;

    info!("Server listening on 0.0.0.0:{port}");

    Server::new(acceptor).serve(router).await;

    Ok(())
}
