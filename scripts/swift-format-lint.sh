#!/bin/bash

# Swift Format Lint Script
# Add this as a "Run Script" build phase in Xcode
# This will check formatting without modifying files

# Only run on main target builds, not for indexing/previews
if [ "${CONFIGURATION}" = "Debug" ] && [ "${ENABLE_PREVIEWS}" = "YES" ]; then
    exit 0
fi

# Check if swift-format is installed
if ! command -v swift-format &> /dev/null; then
    echo "warning: swift-format not installed. Install with: brew install swift-format"
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
swift-format lint --strict --parallel $SWIFT_FILES
