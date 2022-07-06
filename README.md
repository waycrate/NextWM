# NextWM

Manual tiling wayland compositor written with wlroots aimed to be a bspwm clone.

Note: NextWM is still a work in progress project. It won't be useable anytime soon, but when it is I will be the first one to spam screenshots of it in the readme.

## License:

The entire project is licensed as BSD-2 "Simplified" unless stated otherwise in the file header.

## Aim

I want to learn how to write wlroots compositors with this project and keep everything commented to a great extent for others to learn from.
The wlroots ecosystem is hard to initially get into as per my experience and I want to change that via NextWM.

## Building

### Depedencies

1. `libinput`
1. `make`
1. `pixman`
1. `pkg-config`
1. `scdoc` (Optional. If scdoc binary is not found, man pages are not generated.)
1. `wayland-protocols`
1. `wayland`
1. `wlroots` 0.15
1. `xkbcommon`
1. `zig` 0.9.1

## Steps

```bash
git clone --recursive https://github.com/waycrate/NextWM;cd NextWM
sudo make install
```

## Support

-   https://matrix.to/#/#waycrate-tools:matrix.org
-   https://discord.gg/KKZRDYrRYW
