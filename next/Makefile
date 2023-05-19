# If you update this, change .gitignore too!
BIN = next

PROTOCOL_DIR = protocols

CFLAGS += -Wall -Werror -Wextra -Wpedantic -Wno-unused-parameter -Wconversion -Wformat-security -Wformat -Wsign-conversion -Wfloat-conversion -DWLR_USE_UNSTABLE -I./$(PROTOCOL_DIR) -I../deps/wlroots/include/wlr
CFLAGS += -Wunused-result -I./include -fsanitize=leak -fsanitize=address -std=c++17

LDFLAGS +=

SRC = $(wildcard src/*.cpp)
OBJ = $(patsubst src/%.cpp, src/%.o, $(SRC))

XML_FILES = $(wildcard $(PROTOCOL_DIR)/*.xml)
PROTOCOL_HEADERS = $(patsubst $(PROTOCOL_DIR)/%.xml,$(PROTOCOL_DIR)/%-protocol.h,$(XML_FILES))

PKGS = wayland-server wlroots

CFLAGS += $(foreach p,$(PKGS),$(shell pkg-config --cflags $(p)))
LDLIBS += $(foreach p,$(PKGS),$(shell pkg-config --libs $(p)))

$(BIN): $(PROTOCOL_HEADERS) $(OBJ)
	$(CXX) $(LDFLAGS) $(CFLAGS) $(LDLIBS) -o $@ $(OBJ)

$(OBJ):
	$(CXX) $(LDFLAGS) $(CFLAGS) $(LDLIBS) -c -o $@ $(subst .o,.cpp,$@)

$(PROTOCOL_HEADERS):
	@wayland-scanner server-header $(subst -protocol.h,.xml,$@) $@

clean:
	$(RM) $(BIN) $(OBJ) $(PROTOCOL_DIR)/*.h

.PHONY: clean
