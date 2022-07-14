WAYLAND_SCANNER = $(shell pkg-config --variable=wayland_scanner wayland-scanner)

CFLAGS += -Wall -Werror -Wextra -Wpedantic -Wno-unused-parameter -Wconversion -Wformat-security -Wformat -Wsign-conversion -Wfloat-conversion
CFLAGS += -Wunused-result -fsanitize=leak -std=c18

OBJ = nextctl.o next-control-v1.o
GEN = next-control-v1.c next-control-v1.h

PKGS = wayland-client

CFLAGS += $(foreach p,$(PKGS),$(shell pkg-config --cflags $(p)))
LDLIBS += $(foreach p,$(PKGS),$(shell pkg-config --libs $(p)))

nextctl: $(OBJ)
	$(CC) $(LDFLAGS) -o $@ $(OBJ) $(CFLAGS) $(LDLIBS)

$(OBJ): $(GEN)

%.c: %.xml
	$(WAYLAND_SCANNER) private-code < $< > $@

%.h: %.xml
	$(WAYLAND_SCANNER) client-header < $< > $@

clean:
	$(RM) nextctl $(GEN) $(OBJ)

.PHONY: clean install
