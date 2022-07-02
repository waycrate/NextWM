PREFIX=/usr
BINDIR=$(PREFIX)/bin

all: build

build:
	zig build -Drelease-safe

fast:
	zig build -Drelease-fast

small:
	zig build -Drelease-small

install: build
	zig build --prefix $(PREFIX)

uninstall:
	$(RM) -f $(PREFIX)/bin/next
	$(RM) -f $(PREFIX)/bin/nextctl
	$(RM) -f $(PREFIX)/share/man/man1/next.1
	$(RM) -f $(PREFIX)/share/man/man1/nextctl.1
	$(RM) -f $(PREFIX)/share/wayland-sessions/next.desktop

clean:
	$(RM) -rf zig-cache zig-out
	$(MAKE) -C ./nextctl -s $@
	$(RM) -f ./doc/*.1

.PHONY: build fast clean install
