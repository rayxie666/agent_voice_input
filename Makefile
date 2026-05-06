.PHONY: setup build app run permit release dmg clean clean-all

APP_NAME := VoiceInput
APP_BUNDLE := build/$(APP_NAME).app
BIN := .build/release/$(APP_NAME)

# Override on the make command line: `make release VERSION=0.1.1`
VERSION ?= 0.1.0
RELEASE_DMG := build/$(APP_NAME)-$(VERSION).dmg
DMG_STAGING := build/dmg-staging

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

# Build a distributable DMG (drag .app to /Applications) for GitHub Releases.
# Requires `create-dmg`: brew install create-dmg
dmg: app
	@command -v create-dmg >/dev/null 2>&1 || { \
	    echo "ERROR: create-dmg not installed. Run: brew install create-dmg"; \
	    exit 1; \
	}
	@rm -rf "$(DMG_STAGING)" "$(RELEASE_DMG)"
	@mkdir -p "$(DMG_STAGING)"
	cp -R "$(APP_BUNDLE)" "$(DMG_STAGING)/"
	# create-dmg lays out a 540x380 window with the .app at left and a
	# symlink to /Applications at right — the canonical "drag here" UX.
	# --skip-jenkins: don't fail on stale .DS_Store; --no-internet-enable:
	# don't auto-mount on download (avoids "missing internet enable" warnings).
	create-dmg \
	    --volname "$(APP_NAME) $(VERSION)" \
	    --window-pos 200 120 \
	    --window-size 540 380 \
	    --icon-size 100 \
	    --icon "$(APP_NAME).app" 130 180 \
	    --hide-extension "$(APP_NAME).app" \
	    --app-drop-link 410 180 \
	    --skip-jenkins \
	    "$(RELEASE_DMG)" \
	    "$(DMG_STAGING)"
	@rm -rf "$(DMG_STAGING)"
	@echo
	@echo "==> Built $(RELEASE_DMG)"
	@echo "==> SHA-256:"
	@shasum -a 256 "$(RELEASE_DMG)"

# Top-level "make release" entry: produces the DMG and prints upload hints.
release: dmg
	@echo
	@echo "Upload manually with:"
	@echo "    gh release create v$(VERSION) $(RELEASE_DMG) --generate-notes"
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
