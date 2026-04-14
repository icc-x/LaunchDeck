#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LaunchDeck"
BUNDLE_ID="com.icc.launchdeck"
MIN_SYSTEM_VERSION="26.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
ICON_NAME="AppIcon"
ICON_FILE="$ICON_NAME.icns"
ICON_SOURCE="$ROOT_DIR/Resources/$ICON_FILE"
ARM64_TRIPLE="arm64-apple-macosx26.0"
X86_64_TRIPLE="x86_64-apple-macosx26.0"
ARM64_BUILD_DIR="$ROOT_DIR/.build/arm64-apple-macosx/release"
X86_64_BUILD_DIR="$ROOT_DIR/.build/x86_64-apple-macosx/release"
DEFAULT_APP_VERSION="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
APP_VERSION="${APP_VERSION:-${DEFAULT_APP_VERSION:-1.0.0}}"
APP_BUILD="${APP_BUILD:-$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)}"

TARGET_ARCH="arm64"
SKIP_ZIP=0

usage() {
  cat <<EOF
usage: $0 [--arch arm64|x86_64|universal] [--skip-zip]

environment:
  APP_VERSION       override CFBundleShortVersionString
  APP_BUILD         override CFBundleVersion
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || {
        echo "missing value for --arch" >&2
        exit 2
      }
      TARGET_ARCH="$2"
      shift 2
      ;;
    --skip-zip)
      SKIP_ZIP=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$TARGET_ARCH" in
  arm64)
    RELEASE_DIR="$DIST_DIR/release-arm64"
    ZIP_LABEL="macos-arm64"
    ;;
  x86_64)
    RELEASE_DIR="$DIST_DIR/release-x86_64"
    ZIP_LABEL="macos-x86_64"
    ;;
  universal)
    RELEASE_DIR="$DIST_DIR/release-universal"
    ZIP_LABEL="macos-universal"
    ;;
  *)
    echo "unsupported arch: $TARGET_ARCH" >&2
    usage >&2
    exit 2
    ;;
esac

APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ZIP_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION-$ZIP_LABEL.zip"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "missing app icon: $ICON_SOURCE" >&2
  exit 1
fi

build_release() {
  local triple="$1"
  local label="$2"
  echo "[$label] Building release binary"
  swift build -c release --triple "$triple"
}

copy_resource_bundle() {
  local build_dir="$1"
  local bundle_path="$build_dir/${APP_NAME}_${APP_NAME}.bundle"
  if [[ -d "$bundle_path" ]]; then
    cp -R "$bundle_path" "$APP_RESOURCES/"
  fi
}

echo "[1/6] Preparing $TARGET_ARCH package"
case "$TARGET_ARCH" in
  arm64)
    build_release "$ARM64_TRIPLE" "1/6"
    ;;
  x86_64)
    build_release "$X86_64_TRIPLE" "1/6"
    ;;
  universal)
    build_release "$ARM64_TRIPLE" "1/6"
    build_release "$X86_64_TRIPLE" "2/6"
    ;;
esac

echo "[2/6] Staging app bundle"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

echo "[3/6] Installing application binary"
case "$TARGET_ARCH" in
  arm64)
    cp "$ARM64_BUILD_DIR/$APP_NAME" "$APP_BINARY"
    copy_resource_bundle "$ARM64_BUILD_DIR"
    ;;
  x86_64)
    cp "$X86_64_BUILD_DIR/$APP_NAME" "$APP_BINARY"
    copy_resource_bundle "$X86_64_BUILD_DIR"
    ;;
  universal)
    lipo -create \
      "$ARM64_BUILD_DIR/$APP_NAME" \
      "$X86_64_BUILD_DIR/$APP_NAME" \
      -output "$APP_BINARY"
    copy_resource_bundle "$ARM64_BUILD_DIR"
    ;;
esac
chmod +x "$APP_BINARY"
cp "$ICON_SOURCE" "$APP_RESOURCES/$ICON_FILE"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>$ICON_NAME</string>
  <key>CFBundleIconName</key>
  <string>$ICON_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "[4/6] Ad-hoc signing app bundle"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "[5/6] Verifying package"
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ "$SKIP_ZIP" -eq 0 ]]; then
  echo "[6/6] Creating zip archive"
  rm -f "$ZIP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"
else
  echo "[6/6] Skipping zip archive"
fi

echo "arch=$TARGET_ARCH"
echo "app_bundle=$APP_BUNDLE"
if [[ "$SKIP_ZIP" -eq 0 ]]; then
  echo "zip_archive=$ZIP_PATH"
fi
