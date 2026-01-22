#!/bin/bash
# Build BugSplat.xcframework for all platforms (iOS, macOS, tvOS)
# PLCrashReporter static libraries are in Vendor/PLCrashReporter/

set -e

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
