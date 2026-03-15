# HAnSKELLsen — DSL compiler and normative audit backend
# Single binary: audit, quantale analysis, IR-to-DSL

.PHONY: build install run test clean

BIN_DIR := bin
BINARY := hanskellsen
DEFAULT_INPUT := lawlib/instantiations/composed_lease_regime.dsl

# Build the binary
build:
	cabal build exe:$(BINARY)

# Install binary to bin/ for single-command use (copy from build output)
install: build
	@mkdir -p $(BIN_DIR)
	@BIN_PATH=$$(cabal list-bin exe:$(BINARY) 2>/dev/null) && \
		cp "$$BIN_PATH" $(BIN_DIR)/$(BINARY) && \
		echo "Installed. Run: ./$(BIN_DIR)/$(BINARY) [args]"

# Run with default input (audit mode)
run: build
	cabal run exe:$(BINARY) -- $(or $(ARGS),$(DEFAULT_INPUT))

# Run all instantiations
run-all: build
	@for f in lawlib/instantiations/*.dsl; do \
		echo "=== $$f ==="; \
		cabal run exe:$(BINARY) -- "$$f" 2>&1 | head -25; \
		echo ""; \
	done

# Run tests
test:
	cabal test

# Clean build artifacts
clean:
	cabal clean
	rm -rf $(BIN_DIR)
