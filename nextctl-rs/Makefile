BUILD_FLAGS = --release

all: build

build:
	cargo build $(BUILD_FLAGS)

check:
	cargo check
	cargo fmt -- --check

clean:
	cargo clean

.PHONY: all build protocols clean check
