{
  description = "NextWM devel";

  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable"; };

  outputs = { self, nixpkgs, ... }:
    let
      pkgsFor = system:
        import nixpkgs {
          inherit system;
          overlays = [ ];
        };

      targetSystems = [ "aarch64-linux" "x86_64-linux" ];
    in {
      devShells = nixpkgs.lib.genAttrs targetSystems (system:
        let pkgs = pkgsFor system;
        in {
          default = pkgs.mkShell {
            name = "NextWM-devel";

            nativeBuildInputs = with pkgs; [
              # Compilers
              cargo
              go
              rustc
              scdoc
              zig

              # Libs
              cairo
              hwdata
              libGL
              libdrm
              libevdev
              libinput
              libjpeg
              libxkbcommon
              mesa
              pixman
              stdenv
              udev
              wayland
              wayland-protocols
              wlroots_0_16
              (callPackage ./scenefx.nix { })

              # Tools
              clang-tools
              cmake
              gdb
              gnumake
              gopls
              meson
              ninja
              pkg-config
              rust-analyzer
              rustfmt
              strace
              valgrind
              wayland-scanner
              zls
            ];
          };
        });
    };
}
