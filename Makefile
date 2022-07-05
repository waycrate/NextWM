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
