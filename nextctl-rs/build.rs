extern crate wayland_scanner;
use std::path::Path;

pub fn main() {
    let out_dir = Path::new(concat!(env!("CARGO_MANIFEST_DIR"), "/src/wayland/"));
    wayland_scanner::generate_code(
        "../protocols/next-control-v1.xml",
        out_dir.join("next_control_v1.rs"),
        wayland_scanner::Side::Client,
    );
}
