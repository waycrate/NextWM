PREFIX=/usr
BINDIR=$(PREFIX)/bin
BUILD_FLAGS = -Drelease-safe

build:
	zig build $(BUILD_FLAGS)

install:
	zig build $(BUILD_FLAGS) --prefix $(PREFIX)

check:
	zig fmt --check next/
	zig fmt --check *.zig
	$(MAKE) -C ./nextctl -s $@
	$(MAKE) -C ./nextctl-rs -s $@
	$(MAKE) -C ./nextctl-go -s $@

uninstall:
	$(RM) $(PREFIX)/bin/next
	$(RM) $(PREFIX)/bin/nextctl
	$(RM) $(PREFIX)/share/man/man1/next.1.gz
	$(RM) $(PREFIX)/share/man/man1/nextctl.1.gz
	$(RM) $(PREFIX)/share/wayland-sessions/next.desktop
	$(RM) $(PREFIX)/share/next-protocols/next-control-v1.xml
	$(RM) $(PREFIX)/share/pkgconfig/next-protocols.pc

clean:
	$(MAKE) -C ./nextctl -s $@
	$(MAKE) -C ./nextctl-go -s $@
	$(MAKE) -C ./nextctl-rs -s $@
	$(RM) -r zig-cache zig-out
	$(RM) ./docs/*.gz
	$(RM) *.pc


.PHONY: build clean install uninstall check
