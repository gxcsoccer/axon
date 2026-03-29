PREFIX ?= /usr/local
BINARY = axon
BUILD_DIR = .build/release

.PHONY: build install uninstall clean test

build:
	swift build -c release

test:
	swift test

install: build
	@if [ ! -w "$(PREFIX)/bin" ]; then \
		echo "Need sudo to install to $(PREFIX)/bin"; \
		sudo install -d "$(PREFIX)/bin"; \
		sudo install "$(BUILD_DIR)/$(BINARY)" "$(PREFIX)/bin/$(BINARY)"; \
	else \
		install -d "$(PREFIX)/bin"; \
		install "$(BUILD_DIR)/$(BINARY)" "$(PREFIX)/bin/$(BINARY)"; \
	fi
	@echo ""
	@echo "✓ Installed axon to $(PREFIX)/bin/$(BINARY)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run 'axon permissions' to check macOS permissions"
	@echo "  2. Grant Accessibility: System Settings > Privacy & Security > Accessibility"
	@echo "  3. Grant Screen Recording: System Settings > Privacy & Security > Screen Recording"
	@echo "  4. Run 'axon --help' to see all commands"

uninstall:
	@if [ ! -w "$(PREFIX)/bin" ]; then \
		sudo rm -f "$(PREFIX)/bin/$(BINARY)"; \
	else \
		rm -f "$(PREFIX)/bin/$(BINARY)"; \
	fi
	@echo "✓ Uninstalled axon"

clean:
	swift package clean
	rm -rf .build
