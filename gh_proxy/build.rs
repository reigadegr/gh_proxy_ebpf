fn main() -> Result<(), Box<dyn std::error::Error>> {
    aya_build::build_ebpf(
        [aya_build::Package {
            name: "gh_proxy-ebpf",
            root_dir: "../gh_proxy-ebpf",
            no_default_features: false,
            features: &[],
        }],
        aya_build::Toolchain::Nightly,
    )?;

    Ok(())
}
