SCANNER := wayland-scanner

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

clean:
	$(RM) nextctl $(GEN) $(OBJ)

.PHONY: clean install
