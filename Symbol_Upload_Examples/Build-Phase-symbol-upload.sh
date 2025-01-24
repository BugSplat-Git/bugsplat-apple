exec > "/tmp/Xcode_run_script.log" 2>&1

# Use osascript(1) to present notification banners; otherwise
osascript -e 'display notification "preparing and uploading symbols…" with title "BugSplat"'

# change this line to point to the downloaded symbol-upload-macos executable, and the parameters of -a, -b, -u, -p
"$PROJECT_DIR"/../../Tools/symbol-upload-macos -a "App Name" -b "Fred" -u "fred@bugsplat.com" -p "Flintstone" -f "**/*.dSYM" -d "$BUILT_PRODUCTS_DIR" -v "1.0 (1)"

