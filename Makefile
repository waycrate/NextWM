PREFIX=/usr
BINDIR=$(PREFIX)/bin
BUILD_FLAGS = -Dxwayland-lazy

build:
	zig build $(BUILD_FLAGS)

install:
	zig build $(BUILD_FLAGS) --prefix $(PREFIX)

check:
	zig fmt --check next/
	zig fmt --check build.zig
	$(MAKE) -C ./nextctl -s $@
	cd ./nextctl-rs; cargo check
	cd ./nextctl-rs; cargo fmt -- --check

uninstall:
	$(RM) $(PREFIX)/bin/next
	$(RM) $(PREFIX)/bin/nextctl
	$(RM) $(PREFIX)/share/man/man1/next.1
	$(RM) $(PREFIX)/share/man/man1/nextctl.1
	$(RM) $(PREFIX)/share/wayland-sessions/next.desktop

clean:
	$(RM) -r zig-cache zig-out
	$(MAKE) -C ./nextctl -s $@
	$(RM) ./docs/*.gz
	cd ./nextctl-rs/; cargo clean

.PHONY: build clean install uninstall check
