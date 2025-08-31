# Binary name (your CLI command)
BIN=swiftcli
PREFIX=/usr/local/bin

# Build the project
build:
	swift build -c release

# Install the binary system-wide
install: build
	cp .build/release/$(BIN) $(PREFIX)/$(BIN)

# Uninstall the binary
uninstall:
	rm -f $(PREFIX)/$(BIN)

# Reinstall (shortcut)
reinstall: uninstall install

# Run tests
test:
	swift test

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build
