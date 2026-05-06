.PHONY: setup build app run permit release clean clean-all

APP_NAME := VoiceInput
APP_BUNDLE := build/$(APP_NAME).app
BIN := .build/release/$(APP_NAME)

# Override on the make command line: `make release VERSION=0.1.1`
VERSION ?= 0.1.0
RELEASE_ZIP := build/$(APP_NAME)-$(VERSION).zip

setup:
	./setup.sh

build:
	swift build -c release

# Bundle the executable into a proper .app so Info.plist & permission prompts work.
app: build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/"; fi
	# Ad-hoc sign so TCC remembers the app between launches.
	codesign --force --deep --sign - --entitlements Resources/VoiceInput.entitlements "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

# Build a distributable zip of the .app for GitHub Releases. We preserve the
# Mach-O signature with `zip -y` (don't follow symlinks; some bundles include
# them) so codesign --verify still passes after unzip.
release: app
	@rm -f "$(RELEASE_ZIP)"
	cd build && zip -r -y "$(APP_NAME)-$(VERSION).zip" "$(APP_NAME).app"
	@echo
	@echo "==> Built $(RELEASE_ZIP)"
	@echo "==> SHA-256:"
	@shasum -a 256 "$(RELEASE_ZIP)"
	@echo
	@echo "Upload manually with:"
	@echo "    gh release create v$(VERSION) $(RELEASE_ZIP) --generate-notes"
	@echo
	@echo "Or push a tag to trigger the GitHub Actions workflow:"
	@echo "    git tag v$(VERSION) && git push origin v$(VERSION)"

# Wipe stale TCC accessibility approval. Run this whenever the UI in System
# Settings shows VoiceInput as enabled but the app's banner says "未授权" —
# that means a rebuild changed the cdhash and the old grant is now orphaned.
# After running this, click "打开授权页" in the app and grant fresh.
permit:
	@echo "Resetting Accessibility approval for com.local.voiceinput..."
	@tccutil reset Accessibility com.local.voiceinput
	@echo "Done. Now: open the app, click '打开授权页', and grant fresh."

clean:
	rm -rf .build build

clean-all: clean
	rm -rf vendor Models
