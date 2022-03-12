# HerbWM

Manual tiling BSPWM clone wayland compositor written with wlroots.

Note: HerbWM is still a work in progress project. It won't be useable anytime soon, but when it is I will be the first one to spam screenshots of it in the readme.

Also consider checking out https://github.com/shinyzenith/nim-wl

## Aim

I want to learn how to write wlroots compositors with this project and keep everything commented to a great extent for others to learn from.
The wlroots ecosystem is hard to initially get into as per my experience and I want to change that via HerbWM.

## Building

### Depedencies

1. `zig` 0.9.1
1. `wayland`
1. `wayland-protocols`
1. `wlroots`
1. `pixman`
1. `xkbcommon`

## Steps

```bash
git clone https://github.com/waycrate/herbwm;cd herbwm
git submodule update --init
sudo zig build --prefix/usr/local
```

## Support

- https://matrix.to/#/#waycrate-tools:matrix.org
- https://discord.gg/KKZRDYrRYW
