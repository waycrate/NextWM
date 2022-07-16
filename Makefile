PREFIX=/usr
BINDIR=$(PREFIX)/bin
BUILD_FLAGS =
# ^^^ Possible options:
# -Drelease-safe
# -Drelease-fast
# -Drelease-small
#
# Read zig documentation to find out their usecases.

build:
	zig build $(BUILD_FLAGS)

install:
	zig build $(BUILD_FLAGS) --prefix $(PREFIX)

check:
	zig fmt --check next/
	zig fmt --check build.zig
	$(MAKE) -C ./nextctl -s $@

uninstall:
	$(RM) $(PREFIX)/bin/next
	$(RM) $(PREFIX)/bin/nextctl
	$(RM) $(PREFIX)/share/man/man1/next.1
	$(RM) $(PREFIX)/share/man/man1/nextctl.1
	$(RM) $(PREFIX)/share/wayland-sessions/next.desktop

clean:
	$(RM) -r zig-cache zig-out
	$(MAKE) -C ./nextctl -s $@
	$(RM) ./doc/*.1

.PHONY: build fast clean install
