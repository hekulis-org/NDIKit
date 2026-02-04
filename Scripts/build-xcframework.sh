#!/bin/bash
set -euo pipefail

# Build NDIKitC.xcframework
# Supports: macOS (arm64), iOS device (arm64)
# Note: iOS Simulator not supported - NDI SDK has linker issues when converted

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Building NDIKitC.xcframework...${NC}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_ROOT/Vendor/NDI-SDK"
BUILD_DIR="$PROJECT_ROOT/Build"
FRAMEWORKS_DIR="$PROJECT_ROOT/Frameworks"
XCFRAMEWORK_NAME="NDIKitC.xcframework"

# Verify source files exist
if [ ! -f "$VENDOR_DIR/lib/iOS/libndi_ios.a" ]; then
    echo -e "${RED}Error: iOS library not found${NC}"
    exit 1
fi

if [ ! -f "$VENDOR_DIR/lib/macOS/libndi.dylib" ]; then
    echo -e "${RED}Error: macOS library not found${NC}"
    exit 1
fi

# Clean build directory
echo -e "${YELLOW}Cleaning build directory...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ============================================================================
# Step 1: Extract arm64 slices only
# ============================================================================
echo -e "${YELLOW}Extracting arm64 slices...${NC}"

IOS_LIB="$VENDOR_DIR/lib/iOS/libndi_ios.a"
MACOS_LIB="$VENDOR_DIR/lib/macOS/libndi.dylib"

# Check what architectures we have
echo "iOS library architectures:"
lipo -info "$IOS_LIB"
echo ""
echo "macOS library architectures:"
lipo -info "$MACOS_LIB"
echo ""

# Extract arm64 for iOS device
IOS_DEVICE_DIR="$BUILD_DIR/ios-device"
mkdir -p "$IOS_DEVICE_DIR"

if lipo -info "$IOS_LIB" | grep -q "arm64"; then
    echo "Extracting arm64 for iOS device..."
    lipo "$IOS_LIB" -thin arm64 -output "$IOS_DEVICE_DIR/libndi.a"
else
    echo -e "${RED}Error: No arm64 slice in iOS library${NC}"
    exit 1
fi

# Extract arm64 for macOS
MACOS_DIR="$BUILD_DIR/macos"
mkdir -p "$MACOS_DIR"

if lipo -info "$MACOS_LIB" | grep -q "arm64"; then
    echo "Extracting arm64 for macOS..."
    lipo "$MACOS_LIB" -thin arm64 -output "$MACOS_DIR/libndi.dylib"
else
    echo -e "${RED}Error: No arm64 slice in macOS library${NC}"
    exit 1
fi

# ============================================================================
# Step 2: Create Framework structures
# ============================================================================
echo -e "${YELLOW}Creating framework structures...${NC}"

# Function to create framework structure
create_framework() {
    local PLATFORM=$1
    local BINARY_PATH=$2
    local OUTPUT_DIR=$3
    local IS_DYNAMIC=$4

    echo "  Creating $PLATFORM framework..."

    FRAMEWORK_DIR="$OUTPUT_DIR/NDIKitC.framework"

    # Determine minimum OS version
    local MIN_OS_VERSION="17.5"
    if [ "$PLATFORM" = "MacOSX" ]; then
        MIN_OS_VERSION="15.0"
    fi

    # macOS uses a "deep" versioned bundle structure
    # iOS uses a "shallow" flat bundle structure
    if [ "$PLATFORM" = "MacOSX" ]; then
        # Create versioned directory structure for macOS
        local VERSION_DIR="$FRAMEWORK_DIR/Versions/A"
        mkdir -p "$VERSION_DIR/Headers"
        mkdir -p "$VERSION_DIR/Modules"
        mkdir -p "$VERSION_DIR/Resources"

        # Copy binary
        cp "$BINARY_PATH" "$VERSION_DIR/NDIKitC"
        # Fix install name for dynamic library
        install_name_tool -id "@rpath/NDIKitC.framework/Versions/A/NDIKitC" "$VERSION_DIR/NDIKitC"

        # Copy headers
        if [ -d "$VENDOR_DIR/include" ]; then
            cp "$VENDOR_DIR/include"/*.h "$VERSION_DIR/Headers/" 2>/dev/null || true
        fi

        # Create module.modulemap
        cat > "$VERSION_DIR/Modules/module.modulemap" << 'EOF'
framework module NDIKitC {
    umbrella header "Processing.NDI.Lib.h"
    export *
    module * { export * }
}
EOF

        # Create Info.plist in Resources
        cat > "$VERSION_DIR/Resources/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>NDIKitC</string>
    <key>CFBundleIdentifier</key>
    <string>video.ndi.NDIKitC</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NDIKitC</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$PLATFORM</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>$MIN_OS_VERSION</string>
</dict>
</plist>
EOF

        # Create symlinks for versioned structure
        # Current version symlink
        ln -s "A" "$FRAMEWORK_DIR/Versions/Current"

        # Top-level symlinks pointing to Versions/Current/*
        ln -s "Versions/Current/NDIKitC" "$FRAMEWORK_DIR/NDIKitC"
        ln -s "Versions/Current/Headers" "$FRAMEWORK_DIR/Headers"
        ln -s "Versions/Current/Modules" "$FRAMEWORK_DIR/Modules"
        ln -s "Versions/Current/Resources" "$FRAMEWORK_DIR/Resources"
    else
        # iOS uses shallow (flat) bundle structure
        mkdir -p "$FRAMEWORK_DIR/Headers"
        mkdir -p "$FRAMEWORK_DIR/Modules"

        # Copy binary
        cp "$BINARY_PATH" "$FRAMEWORK_DIR/NDIKitC"

        # Copy headers
        if [ -d "$VENDOR_DIR/include" ]; then
            cp "$VENDOR_DIR/include"/*.h "$FRAMEWORK_DIR/Headers/" 2>/dev/null || true
        fi

        # Create module.modulemap
        cat > "$FRAMEWORK_DIR/Modules/module.modulemap" << 'EOF'
framework module NDIKitC {
    umbrella header "Processing.NDI.Lib.h"
    export *
    module * { export * }
}
EOF

        # Create Info.plist at root level for iOS
        cat > "$FRAMEWORK_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>NDIKitC</string>
    <key>CFBundleIdentifier</key>
    <string>video.ndi.NDIKitC</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NDIKitC</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>$PLATFORM</string>
    </array>
    <key>MinimumOSVersion</key>
    <string>$MIN_OS_VERSION</string>
</dict>
</plist>
EOF
    fi
}

# Create iOS Device Framework (static)
create_framework "iPhoneOS" "$IOS_DEVICE_DIR/libndi.a" "$IOS_DEVICE_DIR" "false"

# Create macOS Framework (dynamic)
create_framework "MacOSX" "$MACOS_DIR/libndi.dylib" "$MACOS_DIR" "true"

# ============================================================================
# Step 3: Create XCFramework
# ============================================================================
echo -e "${YELLOW}Creating XCFramework...${NC}"

rm -rf "$FRAMEWORKS_DIR/$XCFRAMEWORK_NAME"
mkdir -p "$FRAMEWORKS_DIR"

xcodebuild -create-xcframework \
    -framework "$IOS_DEVICE_DIR/NDIKitC.framework" \
    -framework "$MACOS_DIR/NDIKitC.framework" \
    -output "$FRAMEWORKS_DIR/$XCFRAMEWORK_NAME"

# ============================================================================
# Step 4: Verify XCFramework
# ============================================================================
echo -e "${YELLOW}Verifying XCFramework...${NC}"

if [ -d "$FRAMEWORKS_DIR/$XCFRAMEWORK_NAME" ]; then
    echo -e "${GREEN}✓ XCFramework created successfully!${NC}"
    echo ""
    echo "Contents:"
    ls -la "$FRAMEWORKS_DIR/$XCFRAMEWORK_NAME"
    echo ""
    echo "Supported platforms:"
    if command -v plutil &> /dev/null; then
        plutil -p "$FRAMEWORKS_DIR/$XCFRAMEWORK_NAME/Info.plist" | grep -A 2 "LibraryIdentifier" || true
    fi
else
    echo -e "${RED}✗ Failed to create XCFramework${NC}"
    exit 1
fi

# ============================================================================
# Step 5: Clean up
# ============================================================================
echo -e "${YELLOW}Cleaning up...${NC}"
rm -rf "$BUILD_DIR"

echo ""
echo -e "${GREEN}Done! XCFramework is ready at:${NC}"
echo "$FRAMEWORKS_DIR/$XCFRAMEWORK_NAME"
echo ""
echo -e "${GREEN}Supported platforms:${NC}"
echo "  • macOS (arm64) - Apple Silicon Macs"
echo "  • iOS (arm64) - iPhone/iPad devices"
echo ""
echo -e "${YELLOW}Note: iOS Simulator is not supported (NDI SDK limitation)${NC}"
