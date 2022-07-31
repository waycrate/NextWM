use std::{env, error::Error, process::exit};
use wayland_client::{Display, GlobalManager};

mod wayland;
use crate::wayland::next_control_v1::next_command_callback_v1::Event;
use crate::wayland::next_control_v1::next_control_v1::NextControlV1;

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = env::args();
    args.next();
    for flag in args {
        match flag.as_str() {
            "-h" | "--help" => {
                print_usage();
                exit(0);
            }
            "-v" | "--version" => {
                eprintln!(env!("CARGO_PKG_VERSION"));
                exit(0)
            }
            _ => {}
        }
    }
    let display: Display = match Display::connect_to_env() {
        Ok(x) => x,
        Err(_) => {
            eprintln!("ERROR: Cannot connect to wayland display.");
            exit(1);
        }
    };
    let mut event_queue = display.create_event_queue();
    let attached_display = display.attach(event_queue.token());

    let globals = GlobalManager::new(&attached_display);
    if event_queue
        .sync_roundtrip(&mut (), |_, _, _| unreachable!())
        .is_err()
    {
        eprintln!("ERROR: wayland dispatch failed.");
        exit(1);
    };

    let next_control = match globals.instantiate_exact::<NextControlV1>(1) {
        Ok(x) => x,
        Err(_) => {
            eprintln!("ERROR: Compositor doesn't implement NextControlV1.");
            exit(1);
        }
    };

    {
        let mut args = env::args();
        args.next();
        for flag in args {
            next_control.add_argument(flag.to_string());
        }
    }

    let command_callback = next_control.run_command();
    command_callback.quick_assign({
        move |_, event, _| match event {
            Event::Success { output } => {
                println!("{}", output);
            }
            Event::Failure { failure_message } => {
                eprintln!("ERROR: {}", failure_message);
                match failure_message.as_str() {
                    "Unknown command\n" | "No command provided\n" => print_usage(),
                    _ => {}
                }
            }
        }
    });

    if event_queue
        .sync_roundtrip(&mut (), |_, _, _| unreachable!())
        .is_err()
    {
        eprintln!("ERROR: wayland dispatch failed.");
        exit(1);
    };
    Ok(())
}

fn print_usage() {
    eprintln!("Usage: nextctl <command>");
    eprintln!("  -h, --help      Print this help message and exit.");
    eprintln!();
    eprintln!("  -v, --version   Print the version number and exit.");
    eprintln!();
    eprintln!("Complete documentation for recognized commands can be found in");
    eprintln!("the nextctl(1) man page.");
}
