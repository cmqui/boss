SHELL := /bin/bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
LIBBOSS_DIR := $(ROOT_DIR)/packages/libboss
LIBBOSS_APPLE_DIR := $(ROOT_DIR)/packages/libboss-apple
BOSSCTL_DIR := $(ROOT_DIR)/packages/bossctl
BOSS_MACOS_DIR := $(ROOT_DIR)/packages/boss-macos
BOSS_IOS_DIR := $(ROOT_DIR)/packages/boss-ios
BOSS_APPLE_APP_DIR := $(ROOT_DIR)/packages/boss-apple-app
PACKAGING_DIR := $(ROOT_DIR)/packaging
HOMEBREW_PACKAGING_DIR := $(PACKAGING_DIR)/homebrew
HOMEBREW_BUILD_DIR := $(HOMEBREW_PACKAGING_DIR)/build
HOMEBREW_STAGING_DIR := $(HOMEBREW_PACKAGING_DIR)/staging
HOMEBREW_DIST_DIR := $(HOMEBREW_PACKAGING_DIR)/dist
HOMEBREW_RUNTIME_STAGE_DIR := $(HOMEBREW_STAGING_DIR)/libboss
HOMEBREW_BOSSCTL_STAGE_DIR := $(HOMEBREW_STAGING_DIR)/bossctl
HOMEBREW_BOSS_UI_STAGE_DIR := $(HOMEBREW_STAGING_DIR)/boss-ui
HOMEBREW_RUNTIME_ARM64_STAGE_DIR := $(HOMEBREW_RUNTIME_STAGE_DIR)/arm64
HOMEBREW_RUNTIME_X86_64_STAGE_DIR := $(HOMEBREW_RUNTIME_STAGE_DIR)/x86_64
HOMEBREW_BOSSCTL_ARM64_STAGE_DIR := $(HOMEBREW_BOSSCTL_STAGE_DIR)/arm64
HOMEBREW_BOSSCTL_X86_64_STAGE_DIR := $(HOMEBREW_BOSSCTL_STAGE_DIR)/x86_64
SWIFT_CACHE_DIR := $(ROOT_DIR)/.cache
CLANG_MODULE_CACHE_DIR := $(SWIFT_CACHE_DIR)/clang/ModuleCache
SWIFTPM_CACHE_DIR := $(SWIFT_CACHE_DIR)/org.swift.swiftpm

XCODEBUILD ?= xcodebuild
BOSS_RUST_FFI_HOMEBREW_PREFIX ?= /opt/homebrew/opt/libboss
IOS_SIMULATOR ?= iPhone 17 Pro
SWIFT_PACKAGE_FLAGS ?= --disable-sandbox
RELEASE_VERSION ?= 0.0.0-dev
MACOS_ARM64_RUST_TARGET ?= aarch64-apple-darwin
MACOS_X86_64_RUST_TARGET ?= x86_64-apple-darwin
MACOS_ARM64_SWIFT_TRIPLE ?= arm64-apple-macosx14.0
MACOS_X86_64_SWIFT_TRIPLE ?= x86_64-apple-macosx14.0

.PHONY: help \
	ffi-debug ffi-release ffi-ios ffi-ios-device ffi-ios-sim \
	test-rust test-apple test-bossctl test-boss-apple-app test \
	bossctl boss-macos-release-app \
	xcodeproj-macos xcodeproj-ios \
	boss-macos-dynamic boss-macos-static \
	homebrew-runtime homebrew-bossctl homebrew-boss-ui \
	homebrew-stage-runtime homebrew-stage-bossctl homebrew-stage-boss-ui homebrew-stage \
	homebrew-stage-runtime-arm64 homebrew-stage-runtime-x86_64 \
	homebrew-stage-bossctl-arm64 homebrew-stage-bossctl-x86_64 \
	homebrew-stage-release \
	homebrew-archive-runtime-arm64 homebrew-archive-runtime-x86_64 \
	homebrew-archive-bossctl-arm64 homebrew-archive-bossctl-x86_64 \
	homebrew-archive-boss-ui \
	homebrew-archive-release \
	homebrew-package-runtime homebrew-package-bossctl homebrew-package-boss-ui homebrew-package \
	ci

help:
	@printf '%s\n' \
		'Supported targets:' \
		'  ffi-debug             Build macOS debug Rust FFI artifact' \
		'  ffi-release           Build macOS release Rust FFI artifact' \
		'  ffi-ios-device        Build iOS device static Rust FFI artifact' \
		'  ffi-ios-sim           Build iOS simulator static Rust FFI artifact' \
		'  ffi-ios               Build both iOS static Rust FFI artifacts' \
		'  test-rust             Run cargo test in packages/libboss' \
		'  test-apple            Run swift test in packages/libboss-apple' \
		'  test-bossctl          Run swift test in packages/bossctl' \
		'  test-boss-apple-app   Run swift test in packages/boss-apple-app' \
		'  test                  Run repo test targets used in the migration work' \
		'  bossctl               Build bossctl' \
		'  xcodeproj-macos       Generate Boss.xcodeproj' \
		'  xcodeproj-ios         Generate BossiOS.xcodeproj' \
		'  boss-macos-dynamic    Build the macOS app through the dynamic Xcode scheme' \
		'  boss-macos-static     Build the macOS app through the static Xcode scheme' \
		'  boss-macos-release-app Build the self-contained static macOS app bundle' \
		'  homebrew-runtime      Build the shared Homebrew runtime dylib' \
		'  homebrew-bossctl      Build bossctl against the shared Homebrew runtime channel' \
		'  homebrew-boss-ui      Build boss-ui against the shared Homebrew runtime channel' \
		'  homebrew-stage-runtime Stage the libboss dylib for Homebrew packaging' \
		'  homebrew-stage-bossctl Stage the bossctl release binary for Homebrew packaging' \
		'  homebrew-stage-boss-ui Stage the boss-ui app bundle for Homebrew packaging' \
		'  homebrew-stage        Stage the full Homebrew distribution set' \
		'  homebrew-stage-runtime-arm64 Stage the arm64 libboss dylib for Homebrew release packaging' \
		'  homebrew-stage-runtime-x86_64 Stage the x86_64 libboss dylib for Homebrew release packaging' \
		'  homebrew-stage-bossctl-arm64 Stage the arm64 bossctl binary for Homebrew release packaging' \
		'  homebrew-stage-bossctl-x86_64 Stage the x86_64 bossctl binary for Homebrew release packaging' \
		'  homebrew-stage-release Stage the full release-oriented Homebrew artifact set' \
		'  homebrew-archive-runtime-arm64 Archive the arm64 libboss release artifact' \
		'  homebrew-archive-runtime-x86_64 Archive the x86_64 libboss release artifact' \
		'  homebrew-archive-bossctl-arm64 Archive the arm64 bossctl release artifact' \
		'  homebrew-archive-bossctl-x86_64 Archive the x86_64 bossctl release artifact' \
		'  homebrew-archive-boss-ui Archive the universal boss-ui release artifact' \
		'  homebrew-archive-release Build the full set of Homebrew release archives' \
		'  homebrew-package-runtime Show the libboss Homebrew formula path' \
		'  homebrew-package-bossctl Show the bossctl Homebrew formula path' \
		'  homebrew-package-boss-ui Show the boss-ui Homebrew cask path' \
		'  homebrew-package      Show the Homebrew packaging directory' \
		'  ci                    Run the repo verification targets used for CI'

define ensure_swift_cache_dirs
	mkdir -p $(CLANG_MODULE_CACHE_DIR) $(SWIFTPM_CACHE_DIR)
endef

ffi-debug:
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile debug --crate-type cdylib

ffi-release:
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile release --crate-type cdylib

ffi-ios-device:
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile release --target aarch64-apple-ios --crate-type staticlib

ffi-ios-sim:
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile debug --target aarch64-apple-ios-sim --crate-type staticlib

ffi-ios: ffi-ios-device ffi-ios-sim

test-rust:
	cd $(LIBBOSS_DIR) && cargo test

test-apple:
	$(ensure_swift_cache_dirs)
	cd $(LIBBOSS_APPLE_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift test $(SWIFT_PACKAGE_FLAGS)

test-bossctl:
	$(ensure_swift_cache_dirs)
	cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift test $(SWIFT_PACKAGE_FLAGS)

test-boss-apple-app:
	$(ensure_swift_cache_dirs)
	cd $(BOSS_APPLE_APP_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift test $(SWIFT_PACKAGE_FLAGS)

test: test-rust test-apple test-bossctl test-boss-apple-app

bossctl:
	$(ensure_swift_cache_dirs)
	cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift build $(SWIFT_PACKAGE_FLAGS)

xcodeproj-macos:
	cd $(BOSS_MACOS_DIR) && ./scripts/generate-xcodeproj.sh

xcodeproj-ios:
	cd $(BOSS_IOS_DIR) && ./scripts/generate-xcodeproj.sh

boss-macos-dynamic: xcodeproj-macos
	cd $(BOSS_MACOS_DIR) && $(XCODEBUILD) -project Boss.xcodeproj -scheme Boss -configuration Release build

boss-macos-static: xcodeproj-macos
	cd $(BOSS_MACOS_DIR) && $(XCODEBUILD) -project Boss.xcodeproj -scheme "Boss Static" -configuration ReleaseStatic build

boss-macos-release-app:
	cd $(BOSS_MACOS_DIR) && ./scripts/build-release-app.sh

homebrew-runtime:
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile release --crate-type cdylib

homebrew-bossctl: homebrew-runtime
	$(ensure_swift_cache_dirs)
	cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) LIBBOSS_FFI_HOMEBREW_PREFIX=$(BOSS_RUST_FFI_HOMEBREW_PREFIX) swift build $(SWIFT_PACKAGE_FLAGS)

homebrew-boss-ui: xcodeproj-macos homebrew-runtime
	cd $(BOSS_MACOS_DIR) && LIBBOSS_FFI_HOMEBREW_PREFIX=$(BOSS_RUST_FFI_HOMEBREW_PREFIX) $(XCODEBUILD) -project Boss.xcodeproj -scheme Boss -configuration Release build

homebrew-stage-runtime: homebrew-runtime
	mkdir -p $(HOMEBREW_RUNTIME_STAGE_DIR)/lib
	cp -f $(LIBBOSS_DIR)/target/release/libboss_ffi.dylib $(HOMEBREW_RUNTIME_STAGE_DIR)/lib/libboss_ffi.dylib

homebrew-stage-bossctl: homebrew-runtime
	$(ensure_swift_cache_dirs)
	mkdir -p $(HOMEBREW_BOSSCTL_STAGE_DIR)/bin
	cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) LIBBOSS_FFI_HOMEBREW_PREFIX=$(BOSS_RUST_FFI_HOMEBREW_PREFIX) swift build -c release $(SWIFT_PACKAGE_FLAGS)
	cp -f $$(cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift build -c release --show-bin-path $(SWIFT_PACKAGE_FLAGS))/bossctl $(HOMEBREW_BOSSCTL_STAGE_DIR)/bin/bossctl

homebrew-stage-boss-ui: xcodeproj-macos homebrew-runtime
	rm -rf $(HOMEBREW_BUILD_DIR)/boss-ui
	mkdir -p $(HOMEBREW_BOSS_UI_STAGE_DIR)
	cd $(BOSS_MACOS_DIR) && LIBBOSS_FFI_HOMEBREW_PREFIX=$(BOSS_RUST_FFI_HOMEBREW_PREFIX) $(XCODEBUILD) -project Boss.xcodeproj -scheme Boss -configuration Release -derivedDataPath $(HOMEBREW_BUILD_DIR)/boss-ui build
	rm -rf $(HOMEBREW_BOSS_UI_STAGE_DIR)/Boss.app
	cp -R $(HOMEBREW_BUILD_DIR)/boss-ui/Build/Products/Release/Boss.app $(HOMEBREW_BOSS_UI_STAGE_DIR)/Boss.app
	$(HOMEBREW_PACKAGING_DIR)/scripts/prepare-boss-ui.sh $(HOMEBREW_BOSS_UI_STAGE_DIR)/Boss.app

homebrew-stage: homebrew-stage-runtime homebrew-stage-bossctl homebrew-stage-boss-ui

homebrew-stage-runtime-arm64:
	mkdir -p $(HOMEBREW_RUNTIME_ARM64_STAGE_DIR)/lib
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile release --target $(MACOS_ARM64_RUST_TARGET) --crate-type cdylib
	cp -f $(LIBBOSS_DIR)/target/$(MACOS_ARM64_RUST_TARGET)/release/libboss_ffi.dylib $(HOMEBREW_RUNTIME_ARM64_STAGE_DIR)/lib/libboss_ffi.dylib

homebrew-stage-runtime-x86_64:
	mkdir -p $(HOMEBREW_RUNTIME_X86_64_STAGE_DIR)/lib
	cd $(LIBBOSS_DIR) && ./scripts/build-ffi-artifact.sh --profile release --target $(MACOS_X86_64_RUST_TARGET) --crate-type cdylib
	cp -f $(LIBBOSS_DIR)/target/$(MACOS_X86_64_RUST_TARGET)/release/libboss_ffi.dylib $(HOMEBREW_RUNTIME_X86_64_STAGE_DIR)/lib/libboss_ffi.dylib

homebrew-stage-bossctl-arm64:
	$(ensure_swift_cache_dirs)
	mkdir -p $(HOMEBREW_BOSSCTL_ARM64_STAGE_DIR)/bin
	cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) LIBBOSS_FFI_HOMEBREW_PREFIX=$(BOSS_RUST_FFI_HOMEBREW_PREFIX) swift build -c release --triple $(MACOS_ARM64_SWIFT_TRIPLE) $(SWIFT_PACKAGE_FLAGS)
	cp -f $$(cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift build -c release --triple $(MACOS_ARM64_SWIFT_TRIPLE) --show-bin-path $(SWIFT_PACKAGE_FLAGS))/bossctl $(HOMEBREW_BOSSCTL_ARM64_STAGE_DIR)/bin/bossctl

homebrew-stage-bossctl-x86_64:
	$(ensure_swift_cache_dirs)
	mkdir -p $(HOMEBREW_BOSSCTL_X86_64_STAGE_DIR)/bin
	cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) LIBBOSS_FFI_HOMEBREW_PREFIX=/usr/local/opt/libboss swift build -c release --triple $(MACOS_X86_64_SWIFT_TRIPLE) $(SWIFT_PACKAGE_FLAGS)
	cp -f $$(cd $(BOSSCTL_DIR) && CLANG_MODULE_CACHE_PATH=$(CLANG_MODULE_CACHE_DIR) XDG_CACHE_HOME=$(SWIFT_CACHE_DIR) swift build -c release --triple $(MACOS_X86_64_SWIFT_TRIPLE) --show-bin-path $(SWIFT_PACKAGE_FLAGS))/bossctl $(HOMEBREW_BOSSCTL_X86_64_STAGE_DIR)/bin/bossctl

homebrew-stage-release: \
	homebrew-stage-runtime-arm64 \
	homebrew-stage-runtime-x86_64 \
	homebrew-stage-bossctl-arm64 \
	homebrew-stage-bossctl-x86_64 \
	homebrew-stage-boss-ui

homebrew-archive-runtime-arm64: homebrew-stage-runtime-arm64
	mkdir -p $(HOMEBREW_DIST_DIR)
	cd $(HOMEBREW_RUNTIME_ARM64_STAGE_DIR) && tar -czf $(HOMEBREW_DIST_DIR)/libboss-$(RELEASE_VERSION)-macos-arm64.tar.gz lib

homebrew-archive-runtime-x86_64: homebrew-stage-runtime-x86_64
	mkdir -p $(HOMEBREW_DIST_DIR)
	cd $(HOMEBREW_RUNTIME_X86_64_STAGE_DIR) && tar -czf $(HOMEBREW_DIST_DIR)/libboss-$(RELEASE_VERSION)-macos-x86_64.tar.gz lib

homebrew-archive-bossctl-arm64: homebrew-stage-bossctl-arm64
	mkdir -p $(HOMEBREW_DIST_DIR)
	cd $(HOMEBREW_BOSSCTL_ARM64_STAGE_DIR) && tar -czf $(HOMEBREW_DIST_DIR)/bossctl-$(RELEASE_VERSION)-macos-arm64.tar.gz bin

homebrew-archive-bossctl-x86_64: homebrew-stage-bossctl-x86_64
	mkdir -p $(HOMEBREW_DIST_DIR)
	cd $(HOMEBREW_BOSSCTL_X86_64_STAGE_DIR) && tar -czf $(HOMEBREW_DIST_DIR)/bossctl-$(RELEASE_VERSION)-macos-x86_64.tar.gz bin

homebrew-archive-boss-ui: homebrew-stage-boss-ui
	mkdir -p $(HOMEBREW_DIST_DIR)
	rm -f $(HOMEBREW_DIST_DIR)/boss-ui-$(RELEASE_VERSION)-macos-universal.zip
	cd $(HOMEBREW_BOSS_UI_STAGE_DIR) && ditto -c -k --sequesterRsrc --keepParent Boss.app $(HOMEBREW_DIST_DIR)/boss-ui-$(RELEASE_VERSION)-macos-universal.zip

homebrew-archive-release: \
	homebrew-archive-runtime-arm64 \
	homebrew-archive-runtime-x86_64 \
	homebrew-archive-bossctl-arm64 \
	homebrew-archive-bossctl-x86_64 \
	homebrew-archive-boss-ui

homebrew-package-runtime:
	@printf '%s\n' "$(HOMEBREW_PACKAGING_DIR)/Formula/libboss.rb"

homebrew-package-bossctl:
	@printf '%s\n' "$(HOMEBREW_PACKAGING_DIR)/Formula/bossctl.rb"

homebrew-package-boss-ui:
	@printf '%s\n' "$(HOMEBREW_PACKAGING_DIR)/Casks/boss-ui.rb"

homebrew-package:
	@printf '%s\n' "$(HOMEBREW_PACKAGING_DIR)"

ci: test ffi-release ffi-ios-device
