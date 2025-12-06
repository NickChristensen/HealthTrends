#!/bin/bash

# Swift Format Lint Script
# Add this as a "Run Script" build phase in Xcode
# This will check formatting without modifying files

# Only run on main target builds, not for indexing/previews
if [ "${CONFIGURATION}" = "Debug" ] && [ "${ENABLE_PREVIEWS}" = "YES" ]; then
    exit 0
fi

# Check if swift-format is available via Xcode
if ! xcrun swift-format --version &> /dev/null; then
    echo "warning: swift-format not available. Ensure Xcode Command Line Tools are installed."
    exit 0
fi

# Find all Swift files in the project (excluding build artifacts and packages)
SWIFT_FILES=$(find "${SRCROOT}" \
    -name "*.swift" \
    -not -path "*/Build/*" \
    -not -path "*/DerivedData/*" \
    -not -path "*/.build/*" \
    -not -path "*/Pods/*" \
    -not -path "*/.swiftpm/*")

# Run swift-format lint
echo "Running swift-format lint..."
xcrun swift-format lint --strict --parallel $SWIFT_FILES
