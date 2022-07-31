extern crate wayland_client;
extern crate wayland_commons;

pub use wayland::client as next_control_v1;

pub mod wayland {
    #![allow(dead_code, non_camel_case_types, unused_unsafe, unused_variables)]
    #![allow(non_upper_case_globals, non_snake_case, unused_imports)]

    pub mod client {
        pub(crate) use wayland_client::{
            sys,
            sys::common::{wl_argument, wl_array, wl_interface, wl_message},
        };
        pub(crate) use wayland_client::{AnonymousObject, Main, Proxy, ProxyMap};
        pub(crate) use wayland_commons::map::{Object, ObjectMetadata};
        pub(crate) use wayland_commons::smallvec;
        pub(crate) use wayland_commons::wire::{Argument, ArgumentType, Message, MessageDesc};
        pub(crate) use wayland_commons::{Interface, MessageGroup};
        include!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/src/wayland/next_control_v1.rs"
        ));
    }
}
