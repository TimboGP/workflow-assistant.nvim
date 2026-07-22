.PHONY: check lint fmt fmt-check test deps all

LUA_FILES := $(shell find lua plugin -name '*.lua')
PLENARY_DIR := .deps/plenary.nvim

check:
	@fail=0; \
	for f in $(LUA_FILES); do \
		if command -v luac5.1 >/dev/null 2>&1; then \
			luac5.1 -p "$$f" || fail=1; \
		elif command -v luajit >/dev/null 2>&1; then \
			luajit -e "assert(loadfile('$$f'))" || fail=1; \
		else \
			echo "warning: no Lua 5.1 parser found (luac5.1/luajit); falling back to luac" >&2; \
			luac -p "$$f" || fail=1; \
		fi; \
	done; \
	exit $$fail

lint:
	luacheck lua/ plugin/

fmt:
	stylua lua/ plugin/

fmt-check:
	stylua --check lua/ plugin/

deps:
	@if [ ! -d "$(PLENARY_DIR)" ]; then \
		echo "cloning plenary.nvim into $(PLENARY_DIR)..."; \
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$(PLENARY_DIR)"; \
	fi

test: deps
	nvim --headless --noplugin -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}"

all: check lint fmt-check test
