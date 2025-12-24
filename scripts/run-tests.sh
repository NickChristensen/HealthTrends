#!/usr/bin/env bash
# Expects env vars from justfile: PROJECT_FILE, SCHEME_TEST, SIMULATOR, BUILD_DIR
set -u -o pipefail

# Clear test results from previous test runs
rm -rf "$BUILD_DIR/test-results.xcresult"

# Run tests, capture exit code
set +e
xcodebuild test \
    -quiet \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME_TEST" \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -enableCodeCoverage YES \
    -resultBundlePath "$BUILD_DIR/test-results.xcresult" \
    | xcbeautify --disable-logging --is-ci
TEST_EXIT=$?
set -e

# Always extract JSON results
xcrun xcresulttool get \
    --path "$BUILD_DIR/test-results.xcresult" \
    --legacy --format json > "$BUILD_DIR/test-results.json"

# Show failures inline if any
if [ $TEST_EXIT -ne 0 ]; then
    echo ""
    jq '[.actions._values[].actionResult.issues.testFailureSummaries._values[]? | {
        test: .testCaseName._value,
        message: .message._value,
        location: (.documentLocationInCreatingWorkspace.url._value | capture("(?<file>[^/]+\\.swift)#.*StartingLineNumber=(?<line>\\d+)") | "\(.file):\(.line)")
    }]' "$BUILD_DIR/test-results.json"
fi

exit $TEST_EXIT
