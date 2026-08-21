AS      := gcc
ASFLAGS := -c -I src/
AR      := ar
CC      := gcc
CFLAGS  := -no-pie
INSTALL := install

SRC_DIR   := src
BUILD_DIR := build
TEST_DIR  := tests
TEST_BUILD_DIR := $(BUILD_DIR)/tests

SRCS := $(wildcard $(SRC_DIR)/*.S)
OBJS := $(patsubst $(SRC_DIR)/%.S,$(BUILD_DIR)/%.o,$(SRCS))
LIB  := $(BUILD_DIR)/libasmrt.a
INC  := $(SRC_DIR)/asmrt.inc

TEST_SRCS := $(wildcard $(TEST_DIR)/*.S)
TEST_BINS := $(patsubst $(TEST_DIR)/%.S,$(TEST_BUILD_DIR)/%,$(TEST_SRCS))

PREFIX  ?= /usr/local
LIBDIR  := $(PREFIX)/lib

.PHONY: all lib test clean install uninstall

all: lib

lib: $(LIB)

$(LIB): $(OBJS) | $(BUILD_DIR)
	$(AR) rcs $@ $(OBJS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.S $(INC) | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TEST_BUILD_DIR):
	mkdir -p $(TEST_BUILD_DIR)

$(TEST_BUILD_DIR)/%.o: $(TEST_DIR)/%.S $(INC) | $(TEST_BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(TEST_BUILD_DIR)/%: $(TEST_BUILD_DIR)/%.o $(LIB)
	$(CC) $(CFLAGS) $< $(LIB) -o $@

test: $(TEST_BINS)
	@status=0; \
	for t in $(TEST_BINS); do \
		name=$$(basename $$t); \
		out=$$($$t 2>&1); \
		code=$$?; \
		case "$$name" in \
			*_fail) expected=255 ;; \
			*) expected=0 ;; \
		esac; \
		if [ "$$code" -eq "$$expected" ]; then \
			echo "PASS $$name"; \
		else \
			echo "FAIL $$name (exit=$$code, expected=$$expected)"; \
			echo "$$out"; \
			status=1; \
		fi; \
	done; \
	exit $$status

install: $(LIB)
	$(INSTALL) -d $(DESTDIR)$(LIBDIR)
	$(INSTALL) -m 644 $(LIB) $(DESTDIR)$(LIBDIR)/
	$(INSTALL) -d $(DESTDIR)$(INCDIR)
	$(INSTALL) -m 644 $(INC) $(DESTDIR)$(INCDIR)/

uninstall:
	rm -f $(DESTDIR)$(LIBDIR)/$(notdir $(LIB))
	rm -f $(DESTDIR)$(INCDIR)/$(notdir $(INC))

clean:
	rm -rf $(BUILD_DIR)
