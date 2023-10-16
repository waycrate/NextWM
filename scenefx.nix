{ lib, stdenv, fetchFromGitHub, meson, ninja, cmake, pkg-config, wlroots_0_16
, wayland, libdrm, libxkbcommon, udev, pixman, wayland-protocols, libGL, mesa,
}:
stdenv.mkDerivation rec {
  pname = "scenefx";
  version = "unstable-2023-08-06";

  src = fetchFromGitHub {
    owner = "wlrfx";
    repo = "scenefx";
    rev = "b929a2bbadf467864796ad4ec90882ce86cfebff";
    hash = "sha256-c/zRWz6njC3RsHzIcWpd5m7CXGprrIhKENpaQVH7Owk=";
  };

  nativeBuildInputs = [ meson ninja cmake pkg-config ];

  buildInputs = [
    wlroots_0_16
    wayland
    libdrm
    libxkbcommon
    udev
    pixman
    wayland-protocols
    libGL
    mesa
  ];

  meta = with lib; {
    description =
      "A drop-in replacement for the wlroots scene API that allows wayland compositors to render surfaces with eye-candy effects";
    homepage = "https://github.com/wlrfx/scenefx/";
    license = licenses.mit;
    maintainers = with maintainers; [ arjan-s ];
    mainProgram = "scenefx";
    platforms = platforms.all;
  };
}
