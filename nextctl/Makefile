BINARY:=nextctl
BUILD_FLAGS:=

all: build

build:
	zig build $(BUILD_FLAGS)

check:
	$(MAKE) clean -s
	zig fmt --check *.zig
	clang-format -style=file --dry-run --Werror src/*.c
	clang-format -style=file --dry-run --Werror include/*.h

clean:
	$(RM) -r zig-cache zig-out
	$(RM) ./include/next-control-v1.h
	$(RM) ./src/next-control-v1.c

.PHONY: all build clean check
