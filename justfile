set shell := ["bash", "-cu"]
set export

PROJECT := "HealthTrends"
PROJECT_FILE := "HealthTrends.xcodeproj"
SCHEME_APP := "HealthTrends"
SCHEME_TEST := "HealthTrendsWidgetTests"
SIMULATOR := "iPhone 17 Pro"
DERIVED_DATA := "build/DerivedData"
BUILD_DIR := justfile_directory() / "build"

default:
  just --list

build:
    @xcodebuild -project {{PROJECT_FILE}} -scheme {{SCHEME_APP}} -destination 'platform=iOS Simulator,name={{SIMULATOR}}' -derivedDataPath {{DERIVED_DATA}} build | xcbeautify --disable-logging --is-ci

run: build
    @echo "Booting simulator…"
    @xcrun simctl boot "{{SIMULATOR}}" || true
    @echo "Installing app…"
    @xcrun simctl install booted "{{DERIVED_DATA}}/Build/Products/Debug-iphonesimulator/{{PROJECT}}.app"

install-device DEVICE_NAME:
    @xcodebuild -project {{PROJECT_FILE}} -scheme {{SCHEME_APP}} -configuration Release -destination "id={{ if DEVICE_NAME == 'Phone X' { '00008150-001931681E04401C' } else if DEVICE_NAME == 'Biggie V' { '00008027-001251842606802E' } else { error('unknown device ' + DEVICE_NAME + '. Use Phone X or Biggie V.') } }}" -derivedDataPath {{DERIVED_DATA}} build | xcbeautify --disable-logging --is-ci
    @echo "Installing app to {{DEVICE_NAME}}…"
    @xcrun devicectl device install app --device "{{ if DEVICE_NAME == 'Phone X' { '00008150-001931681E04401C' } else if DEVICE_NAME == 'Biggie V' { '00008027-001251842606802E' } else { error('unknown device ' + DEVICE_NAME + '. Use Phone X or Biggie V.') } }}" "{{DERIVED_DATA}}/Build/Products/Release-iphoneos/{{PROJECT}}.app"

test:
    @./scripts/run-tests.sh

lint:
    @echo "Linting…"
    @SRCROOT={{justfile_directory()}} bash scripts/swift-format-lint.sh
