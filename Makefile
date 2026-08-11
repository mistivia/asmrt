AS      := nasm
ASFLAGS := -f elf64 -I src/
AR      := ar
CC      := gcc
CFLAGS  := -no-pie

SRC_DIR   := src
BUILD_DIR := build
TEST_DIR  := tests
TEST_BUILD_DIR := $(BUILD_DIR)/tests

SRCS := $(wildcard $(SRC_DIR)/*.asm)
OBJS := $(patsubst $(SRC_DIR)/%.asm,$(BUILD_DIR)/%.o,$(SRCS))
LIB  := $(BUILD_DIR)/libasmrt.a

TEST_SRCS := $(wildcard $(TEST_DIR)/*.asm)
TEST_BINS := $(patsubst $(TEST_DIR)/%.asm,$(TEST_BUILD_DIR)/%,$(TEST_SRCS))

.PHONY: all lib test clean

all: lib

lib: $(LIB)

$(LIB): $(OBJS) | $(BUILD_DIR)
	$(AR) rcs $@ $(OBJS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.asm | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $< -o $@

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TEST_BUILD_DIR):
	mkdir -p $(TEST_BUILD_DIR)

$(TEST_BUILD_DIR)/%.o: $(TEST_DIR)/%.asm | $(TEST_BUILD_DIR)
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

clean:
	rm -rf $(BUILD_DIR)
