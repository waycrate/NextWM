{ lib, stdenv, fetchFromGitLab, meson, ninja, pkg-config, wayland-scanner, libGL
, wayland, wayland-protocols, libinput, libxkbcommon, pixman, libcap, mesa, xorg
, libpng, ffmpeg_4, hwdata, seatd, vulkan-loader, glslang, nixosTests, xwayland,
}:

stdenv.mkDerivation rec {
  pname = "wlroots";
  version = "1712a7d27444d62f8da8eeedf0840b386a810e96";

  src = fetchFromGitLab {
    domain = "gitlab.freedesktop.org";
    owner = "wlroots";
    repo = "wlroots";
    rev = version;
    hash = "sha256-k7BFx1xvvsdCXNWX0XeZYwv8H/myk4p42i2Y6vjILqM=";
  };

  # $out for the library and $examples for the example programs (in examples):
  outputs = [ "out" "examples" ];

  strictDeps = true;
  depsBuildBuild = [ pkg-config ];

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner glslang hwdata ];

  buildInputs = [
    ffmpeg_4
    libGL
    libcap
    libinput
    libpng
    libxkbcommon
    mesa
    pixman
    seatd
    vulkan-loader
    wayland
    wayland-protocols
    xorg.libX11
    xorg.xcbutilerrors
    xorg.xcbutilimage
    xorg.xcbutilrenderutil
    xorg.xcbutilwm
    xwayland
  ];

  postFixup = ''
    # Install ALL example programs to $examples:
    # screencopy dmabuf-capture input-inhibitor layer-shell idle-inhibit idle
    # screenshot output-layout multi-pointer rotation tablet touch pointer
    # simple
    mkdir -p $examples/bin
    cd ./examples
    for binary in $(find . -executable -type f -printf '%P\n' | grep -vE '\.so'); do
      cp "$binary" "$examples/bin/wlroots-$binary"
    done
  '';

  # Test via TinyWL (the "minimum viable product" Wayland compositor based on wlroots):
  passthru.tests.tinywl = nixosTests.tinywl;

  meta = with lib; {
    description = "A modular Wayland compositor library";
    longDescription = ''
      Pluggable, composable, unopinionated modules for building a Wayland
      compositor; or about 50,000 lines of code you were going to write anyway.
    '';
    homepage = "https://example.com";
    license = licenses.mit;
    platforms = platforms.linux;
    maintainers = with maintainers; [ primeos synthetica ];
  };
}
