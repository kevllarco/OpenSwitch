#!/usr/bin/env bash
# Xcode full-app build phase: bundle the pinned MIT-licensed Logitech helper.
set -euo pipefail
: "${SRCROOT:?}" "${TARGET_BUILD_DIR:?}" "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$resource_dir"
xcrun clang -O2 "$SRCROOT/Tools/DeskSwitchHelper/mxswitch.c" \
    -framework IOKit -framework CoreFoundation -framework CoreGraphics \
    -o "$resource_dir/desk-switch-hid"
cp "$SRCROOT/Tools/DeskSwitchHelper/LICENSE" "$resource_dir/DeskSwitchHelper-LICENSE.txt"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$resource_dir/desk-switch-hid"
fi

# The same stable Keychain reader is used by the Xcode-built app.
xcrun clang -O2 "-DOPENSWITCH_BUNDLE_ID=\"${PRODUCT_BUNDLE_IDENTIFIER}\"" \
    "$SRCROOT/Tools/DeskSwitchKeychain/desk-switch-keychain.c" \
    -framework Security -framework CoreFoundation -o "$resource_dir/desk-switch-keychain"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]; then
    codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$resource_dir/desk-switch-keychain"
fi
