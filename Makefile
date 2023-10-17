PREFIX:=/usr
BUILD_FLAGS:=

build:
	zig build $(BUILD_FLAGS)

install:
	zig build $(BUILD_FLAGS) --prefix $(PREFIX)

check:
	$(MAKE) -C ./nextctl -s $@
	$(MAKE) -C ./nextctl-rs -s $@
	$(MAKE) -C ./nextctl-go -s $@

	zig fmt --check next/
	zig fmt --check *.zig

uninstall:
	$(RM) $(PREFIX)/bin/next
	$(RM) $(PREFIX)/bin/nextctl
	$(RM) $(PREFIX)/share/man/man1/next.1.gz
	$(RM) $(PREFIX)/share/man/man1/nextctl.1.gz
	$(RM) $(PREFIX)/share/wayland-sessions/next.desktop
	$(RM) $(PREFIX)/share/next-protocols/next-control-v1.xml
	$(RM) $(PREFIX)/share/pkgconfig/next-protocols.pc

clean:
	$(MAKE) -C ./nextctl-go -s $@
	$(MAKE) -C ./nextctl-rs -s $@

	$(RM) -r ./nextctl/zig-cache ./nextctl/zig-out
	$(RM) -r zig-cache zig-out
	$(RM) ./docs/*.gz
	$(RM) -r ./deps/scenefx/build
	$(RM) *.pc


.PHONY: build clean install uninstall check
