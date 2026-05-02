#!/bin/sh

set -e

taplo fmt *.toml */*.toml */*/*.toml
export RUSTFLAGS="
    --cfg tokio_unstable
    -C link-arg=-fuse-ld=mold
    -C link-args=-Wl,--gc-sections,--as-needed
"

cargo fmt --all
# 运行 clippy（排除 eBPF 包，因为它是 no_std 目标）
cargo clippy --workspace --exclude gh_proxy-ebpf --all --all-targets --all-features --no-deps
cargo test --workspace --exclude gh_proxy-ebpf
