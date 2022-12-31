BINARY:=nextctl
GO_WAYLAND_SCANNER:=go-wayland-scanner
FMT_REQUIRED:=$(shell gofmt -l $(shell find . -type f -iname *.go))

all: build

build: protocols
	go mod tidy
	go build -ldflags "-s -w" ./cmd/$(BINARY)/

protocols:
	mkdir -p pkg/next_control
	cd pkg/next_control; $(GO_WAYLAND_SCANNER) -i ../../../protocols/next-control-v1.xml -o next_control_v1.go -pkg next_control_v1

check:
	@echo $(FMT_REQUIRED)
	@test -z $(FMT_REQUIRED)

clean:
	go clean
	$(RM) -f $(BINARY)
	$(RM) -f pkg/next_control/next_control_v1.go

.PHONY: all build protocols clean check
