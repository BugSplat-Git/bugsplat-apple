rm -rf Vendor/*
rm -rf archives/*
rm -rf xcframeworks/*
rmdir Vendor
mkdir Vendor
ditto ../plcrashreporter/xcframeworks/CrashReporter.xcframework Vendor/CrashReporter.xcframework
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplat" -destination "generic/platform=iOS" -archivePath "archives/BugSplat-iOS"
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplat" -destination "generic/platform=iOS Simulator" -archivePath "archives/BugSplat-iOS_Simulator"
xcodebuild archive -project BugSplat.xcodeproj -scheme "BugSplatMac" -destination "generic/platform=macOS" -archivePath "archives/BugSplat-macOS"
xcodebuild -create-xcframework -archive archives/BugSplat-iOS.xcarchive -framework BugSplat.framework -archive archives/BugSplat-iOS_Simulator.xcarchive -framework BugSplat.framework -archive archives/BugSplat-macOS.xcarchive -framework BugSplatMac.framework -output xcframeworks/BugSplat.xcframework
# Codesign the xcframework for authenticity. It will get resigned by app developer.
#codesign -s "Apple Distribution: BugSplat, LLC (TN6R4Q475K)"  -f --timestamp xcframeworks/BugSplat.xcframework

