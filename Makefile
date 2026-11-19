# AltLoad: build, test and package from the command line.
#   make            same as make ipa
#   make test       Rust tests for the core and altpair
#   make rust       Rust core → AltLoadFFI.xcframework
#   make project    AltLoad.xcodeproj from project.yml
#   make sim        build for the iOS Simulator
#   make ipa        unsigned Release IPA in build/AltLoad.ipa (ad-hoc signed, like the release workflow)
#   make altpair    altpair.wasm and the altpair installer
#   make clean      remove build output

BUILD   := build
DD      := $(BUILD)/dd
APP     := $(DD)/Build/Products/Release-iphoneos/AltLoad.app
IPA     := $(BUILD)/AltLoad.ipa
NOSIGN  := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" CODE_SIGN_ENTITLEMENTS=""

.PHONY: all test rust project sim ipa altpair clean

all: ipa

test:
	cd core && cargo test
	cd altpair/pair && cargo test
	cd altpair/installer && cargo test

rust:
	bash scripts/build-rust.sh

project:
	xcodegen generate

sim: rust project
	xcodebuild -project AltLoad.xcodeproj -scheme AltLoad -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(BUILD)/dd-sim $(NOSIGN) build -quiet

ipa: rust project
	xcodebuild -project AltLoad.xcodeproj -scheme AltLoad -configuration Release -sdk iphoneos \
		-destination 'generic/platform=iOS' -derivedDataPath $(DD) $(NOSIGN) build -quiet
	rm -rf $(BUILD)/Payload $(IPA)
	mkdir -p $(BUILD)/Payload
	cp -R $(APP) $(BUILD)/Payload/
	find $(BUILD)/Payload -name '.DS_Store' -delete
	for ext in $(BUILD)/Payload/AltLoad.app/PlugIns/*.appex; do \
		[ -d "$$ext" ] && codesign --force --sign - --timestamp=none --generate-entitlement-der "$$ext"; \
	done
	codesign --force --sign - --timestamp=none --generate-entitlement-der $(BUILD)/Payload/AltLoad.app
	cd $(BUILD) && zip -qry -X AltLoad.ipa Payload
	@echo "IPA: $(IPA)"

altpair:
	cd altpair/pair && cargo build --release --target wasm32-wasip1
	cd altpair/installer && cargo build --release

clean:
	rm -rf $(BUILD)
	cd core && cargo clean
