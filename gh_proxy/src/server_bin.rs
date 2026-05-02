use clap::Parser;
use log::info;

use gh_proxy::server;

#[derive(Debug, Parser)]
struct Opt {
    /// Server port
    #[clap(short, long, default_value = "443")]
    port: u16,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let opt = Opt::parse();
    env_logger::init();

    info!("Starting GitHub Proxy Server...");
    info!("Port: {}", opt.port);

    server::run_server(opt.port).await
}
