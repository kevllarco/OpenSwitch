#!/usr/bin/env bash
# Hardware-free security checks. Uses a nonexistent, randomly named pairing item.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/openswitch-keychain-check.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
identity=${OPENSWITCH_SIGNING_IDENTITY:-OpenSwitch Local Development}
keychain="$HOME/Library/Keychains/login.keychain-db"
test_id="dev.kevllar.openswitch.keychain-test.$(uuidgen | tr '[:upper:]' '[:lower:]')"
app="$task_tmp/Parent.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$task_tmp/second"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$test_id</string><key>CFBundleExecutable</key><string>Parent</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
cat > "$task_tmp/parent.swift" <<'SWIFT'
import Foundation
let process = Process()
process.executableURL = Bundle.main.resourceURL!.appendingPathComponent("desk-switch-keychain")
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice
try process.run()
process.waitUntilExit()
print(process.terminationStatus)
SWIFT
for output in "$app/Contents/Resources/desk-switch-keychain" "$task_tmp/second/desk-switch-keychain"; do
    clang -O2 "-DOPENSWITCH_BUNDLE_ID=\"$test_id\"" "$repo/Tools/DeskSwitchKeychain/desk-switch-keychain.c" \
        -framework Security -framework CoreFoundation -o "$output"
    codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$output" 2>/dev/null
done
first_hash=$(codesign -dvvv "$app/Contents/Resources/desk-switch-keychain" 2>&1 | sed -n 's/^CDHash=//p')
second_hash=$(codesign -dvvv "$task_tmp/second/desk-switch-keychain" 2>&1 | sed -n 's/^CDHash=//p')
[[ -n "$first_hash" && "$first_hash" == "$second_hash" ]]
swiftc "$task_tmp/parent.swift" -o "$app/Contents/MacOS/Parent"
codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$app" 2>/dev/null
# Exit 3 means the correct parent was authenticated and the disposable key was absent.
[[ $("$app/Contents/MacOS/Parent") == 3 ]]
set +e
"$app/Contents/Resources/desk-switch-keychain" >/dev/null
shell_status=$?
set -e
[[ $shell_status == 77 ]]
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier dev.kevllar.openswitch.wrong-parent' "$app/Contents/Info.plist"
codesign --force --sign "$identity" --keychain "$keychain" --timestamp=none "$app" 2>/dev/null
[[ $("$app/Contents/MacOS/Parent") == 77 ]]
printf '%s\n' 'Stable helper hash, authenticated parent, wrong parent, and direct invocation checks passed.'
