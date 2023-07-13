{
  description = "NextWM devel";

  inputs = {
    nixgl.url = "github:guibou/nixGL";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs, nixgl, ... }:
    let
      pkgsFor = system:
        import nixpkgs {
          inherit system;
          overlays = [ nixgl.overlay ];
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
              stdenv

              # Libs
              libGL
              libevdev
              libinput
              libxkbcommon
              pixman
              wayland
              wayland-protocols
              wlroots_0_16

              # Tools
              gdb
              rustfmt
              gnumake
              gopls
              pkg-config
              pkgs.nixgl.nixGLMesa # For non-NixOS users who are using the nix package manager.
              rust-analyzer
              strace
              valgrind
              wayland-scanner
              zls
            ];
          };
        });
    };
}
