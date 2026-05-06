.PHONY: setup build app run permit clean clean-all

APP_NAME := VoiceInput
APP_BUNDLE := build/$(APP_NAME).app
BIN := .build/release/$(APP_NAME)

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
