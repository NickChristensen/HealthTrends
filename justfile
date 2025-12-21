set shell := ["bash", "-cu"]

PROJECT := "HealthTrends"
PROJECT_FILE := "HealthTrends.xcodeproj"
SCHEME_APP := "HealthTrends"
SCHEME_TEST := "HealthTrendsWidgetTests"
SIMULATOR := "iPhone 17 Pro"
DERIVED_DATA := "build/DerivedData"

default:
  just --list

build:
    @echo "Building…"
    @xcodebuild -quiet -project {{PROJECT_FILE}} -scheme {{SCHEME_APP}} -destination 'platform=iOS Simulator,name={{SIMULATOR}}' -derivedDataPath {{DERIVED_DATA}} build

run: build
    @echo "Booting simulator…"
    @xcrun simctl boot "{{SIMULATOR}}" || true
    @echo "Installing app…"
    @xcrun simctl install booted "{{DERIVED_DATA}}/Build/Products/Debug-iphonesimulator/{{PROJECT}}.app"

install-device DEVICE_NAME:
    @echo "Building for production…"
    @xcodebuild -quiet -project {{PROJECT_FILE}} -scheme {{SCHEME_APP}} -configuration Release -destination "id={{ if DEVICE_NAME == 'Phone X' { '00008150-001931681E04401C' } else if DEVICE_NAME == 'Biggie V' { '00008027-001251842606802E' } else { error('unknown device ' + DEVICE_NAME + '. Use Phone X or Biggie V.') } }}" -derivedDataPath {{DERIVED_DATA}} build
    @echo "Installing app to {{DEVICE_NAME}}…"
    @xcrun devicectl device install app --device "{{ if DEVICE_NAME == 'Phone X' { '00008150-001931681E04401C' } else if DEVICE_NAME == 'Biggie V' { '00008027-001251842606802E' } else { error('unknown device ' + DEVICE_NAME + '. Use Phone X or Biggie V.') } }}" "{{DERIVED_DATA}}/Build/Products/Release-iphoneos/{{PROJECT}}.app"

test:
    @echo "Building…"
    @xcodebuild test -quiet -project {{PROJECT_FILE}} -scheme {{SCHEME_TEST}} -destination 'platform=iOS Simulator,name={{SIMULATOR}}' -enableCodeCoverage YES

test-results RESULT_BUNDLE:
    @xcodebuild test -project {{PROJECT_FILE}} -scheme {{SCHEME_TEST}} -destination 'platform=iOS Simulator,name={{SIMULATOR}}' -enableCodeCoverage YES -resultBundlePath {{RESULT_BUNDLE}}

lint:
    @echo "Linting…"
    @SRCROOT={{justfile_directory()}} bash scripts/swift-format-lint.sh
