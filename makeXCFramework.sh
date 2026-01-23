#!/bin/bash
# Build BugSplat.xcframework for all platforms (iOS, macOS, tvOS)
# PLCrashReporter is built from source with BugSplat namespace prefix
#
# Usage:
#   ./makeXCFramework.sh                      # Build (uses cached PLCrashReporter if available)
#   ./makeXCFramework.sh --rebuild-plcrashreporter  # Force rebuild PLCrashReporter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLCRASHREPORTER_DIR="$SCRIPT_DIR/Vendor/PLCrashReporter"
PLCRASHREPORTER_XCFRAMEWORK="$PLCRASHREPORTER_DIR/CrashReporter.xcframework"

# Check for --rebuild-plcrashreporter flag
if [ "$1" == "--rebuild-plcrashreporter" ]; then
    echo "Force rebuilding PLCrashReporter..."
    rm -rf "$PLCRASHREPORTER_XCFRAMEWORK"
fi

# Build PLCrashReporter if xcframework doesn't exist
if [ ! -d "$PLCRASHREPORTER_XCFRAMEWORK" ]; then
    echo "Building PLCrashReporter with BugSplat namespace prefix..."
    
    cd "$PLCRASHREPORTER_DIR"
    
    # Build for each platform
    echo "  Building iOS device..."
    xcodebuild -scheme "CrashReporter iOS Framework" -configuration Release -sdk iphoneos \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -quiet
    
    echo "  Building iOS simulator..."
    xcodebuild -scheme "CrashReporter iOS Framework" -configuration Release -sdk iphonesimulator \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -quiet
    
    echo "  Building macOS..."
    xcodebuild -scheme "CrashReporter macOS Framework" -configuration Release \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -quiet
    
    echo "  Building tvOS device..."
    xcodebuild -scheme "CrashReporter tvOS Framework" -configuration Release -sdk appletvos \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -quiet
    
    echo "  Building tvOS simulator..."
    xcodebuild -scheme "CrashReporter tvOS Framework" -configuration Release -sdk appletvsimulator \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES SKIP_INSTALL=NO -quiet
    
    # Find the DerivedData path
    DERIVED_DATA=$(xcodebuild -scheme "CrashReporter iOS Framework" -configuration Release -sdk iphoneos -showBuildSettings 2>/dev/null | grep -m 1 "BUILD_DIR" | awk '{print $3}' | sed 's|/Build/Products||')
    PRODUCTS_DIR="$DERIVED_DATA/Build/Products"
    
    echo "  Creating CrashReporter.xcframework..."
    xcodebuild -create-xcframework \
        -framework "$PRODUCTS_DIR/Release-iphoneos/CrashReporter.framework" \
        -framework "$PRODUCTS_DIR/Release-iphonesimulator/CrashReporter.framework" \
        -framework "$PRODUCTS_DIR/Release-macosx/CrashReporter.framework" \
        -framework "$PRODUCTS_DIR/Release-appletvos/CrashReporter.framework" \
        -framework "$PRODUCTS_DIR/Release-appletvsimulator/CrashReporter.framework" \
        -output "$PLCRASHREPORTER_XCFRAMEWORK"
    
    echo "PLCrashReporter.xcframework built successfully!"
    cd "$SCRIPT_DIR"
else
    echo "Using existing PLCrashReporter xcframework at $PLCRASHREPORTER_XCFRAMEWORK"
fi

# Clean up previous builds
rm -rf archives/*
rm -rf xcframeworks/BugSplat.xcframework

mkdir -p archives
mkdir -p xcframeworks

# Build iOS
echo "Building iOS..."
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplat" -destination "generic/platform=iOS" -archivePath "archives/BugSplat-iOS" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build iOS Simulator
echo "Building iOS Simulator..."
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplat" -destination "generic/platform=iOS Simulator" -archivePath "archives/BugSplat-iOS_Simulator" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build macOS
echo "Building macOS..."
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplatMac" -destination "generic/platform=macOS" -archivePath "archives/BugSplat-macOS" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build tvOS
echo "Building tvOS..."
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplatTV" -destination "generic/platform=tvOS" -archivePath "archives/BugSplat-tvOS" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build tvOS Simulator
echo "Building tvOS Simulator..."
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplatTV" -destination "generic/platform=tvOS Simulator" -archivePath "archives/BugSplat-tvOS_Simulator" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create xcframework directly in xcframeworks folder
echo "Creating xcframeworks/BugSplat.xcframework..."
xcodebuild -create-xcframework \
    -archive archives/BugSplat-iOS.xcarchive -framework BugSplat.framework \
    -archive archives/BugSplat-iOS_Simulator.xcarchive -framework BugSplat.framework \
    -archive archives/BugSplat-macOS.xcarchive -framework BugSplatMac.framework \
    -archive archives/BugSplat-tvOS.xcarchive -framework BugSplatTV.framework \
    -archive archives/BugSplat-tvOS_Simulator.xcarchive -framework BugSplatTV.framework \
    -output xcframeworks/BugSplat.xcframework

echo "Done! xcframeworks/BugSplat.xcframework created."
echo ""
echo "For SPM distribution, zip and upload:"
echo "  cd xcframeworks && zip -r BugSplat.xcframework.zip BugSplat.xcframework"
echo ""
echo "Then update Package.swift with the new URL and checksum."
