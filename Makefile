APP        := yue-hidpi
PREFIX     ?= /usr/local
BINDIR     ?= $(PREFIX)/bin
BUILD      := .build/release
UNIVERSAL  := .build/universal/$(APP)

.PHONY: all build test selftest universal install uninstall clean fmt lint

all: build

build:
	swift build -c release
	@echo "→ $(BUILD)/$(APP)"

test:
	swift test

## Verifies the built binary against the invariants Apple's own override
## files imply. Works with Command Line Tools only, no Xcode needed.
selftest: build
	$(BUILD)/$(APP) selftest

## arm64 + x86_64 in one file; the tool is macOS-only, so this is the
## artefact to attach to a release.
## Note: `swift build --arch arm64 --arch x86_64` needs a full Xcode
## (it shells out to xcbuild). Cross-compiling per triple works with
## Command Line Tools alone, which is what this target uses.
## Separate --scratch-path keeps .build/release (native) untouched, so a
## universal build never leaves you with an arm64-only .build/release on
## an Intel machine ("Bad CPU type in executable").
universal:
	swift build -c release --triple arm64-apple-macosx11.0  --scratch-path .build/arm64
	swift build -c release --triple x86_64-apple-macosx11.0 --scratch-path .build/x86
	mkdir -p .build/universal
	lipo -create -output $(UNIVERSAL) \
		.build/arm64/arm64-apple-macosx/release/$(APP) \
		.build/x86/x86_64-apple-macosx/release/$(APP)
	lipo -info $(UNIVERSAL)
	@echo "→ $(UNIVERSAL)"

install: build
	install -d $(BINDIR)
	install -m 0755 $(BUILD)/$(APP) $(BINDIR)/$(APP)
	@echo "已安装到 $(BINDIR)/$(APP)"

uninstall:
	rm -f $(BINDIR)/$(APP)

clean:
	swift package clean
	rm -rf .build/universal

fmt:
	swift format --in-place --recursive Sources Tests 2>/dev/null || \
		echo "swift format 不可用（需要 Xcode 16+ 工具链）"
