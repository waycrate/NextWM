BINARY:=nextctl
FMT_REQUIRED:=$(shell gofmt -l $(shell find . -type f -iname *.go))
BUILD_FLAGS:=-ldflags "-s -w"

all: build

build:
	go mod tidy
	$(MAKE) generate -s
	go build $(BUILD_FLAGS) ./cmd/$(BINARY)/

generate:
	go generate -x ./...

check:
	$(MAKE) generate -s
	@echo $(FMT_REQUIRED)
	@test -z $(FMT_REQUIRED)
	go vet ./...

clean:
	go clean
	$(RM) -f $(BINARY)
	$(RM) -f pkg/next_control/next_control_v1.go

.PHONY: all build clean check
