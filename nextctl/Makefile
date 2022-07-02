SCANNER := wayland-scanner

PREFIX=/usr/local
BINDIR=$(PREFIX)/bin
MANDIR=$(PREFIX)/share/man

CFLAGS=-Wall -Werror -Wextra -Wpedantic -Wno-unused-parameter -Wconversion -Wformat-security -Wformat -Wsign-conversion -Wfloat-conversion -Wunused-result -fsanitize=leak
LIBS=-lwayland-client
OBJ=nextctl.o next-control-v1.o
GEN=next-control-v1.c next-control-v1.h

nextctl: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(LIBS)

$(OBJ): $(GEN)

%.c: %.xml
	$(SCANNER) private-code < $< > $@

%.h: %.xml
	$(SCANNER) client-header < $< > $@

install: nextctl
	install        -D nextctl            $(DESTDIR)$(BINDIR)/nextctl
	install -m 644 -D nextctl.1          $(DESTDIR)$(MANDIR)/man1/nextctl.1

uninstall:
	$(RM) $(DESTDIR)$(BINDIR)/nextctl
	$(RM) $(DESTDIR)$(MANDIR)/man1/nextctl.1

clean:
	$(RM) nextctl $(GEN) $(OBJ)

.PHONY: clean install

