#!/usr/bin/env bash
# Builds the spotifyglass tweak and injects it (plus FLEX) into a decrypted Spotify IPA.
#
#   scripts/pipeline.sh <decrypted.ipa> [-o out.ipa] [--no-flex] [--install] [--name N] [--icon P.png]   (or: make build / make install)
#
# --install hands the result to install.sh (sign with your certificate, push to the plugged-in iPhone).
#
# The IPA is yours to supply: drop a decrypted Spotify .ipa in ipa/ and the Makefile finds it.
#
# Needs: Theos in $THEOS (default ~/theos), an iPhoneOS 26+ SDK from the selected Xcode or in $THEOS/sdks,
# gmake, ldid, dpkg-deb (brew) and cyan (uv tool install "cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw").
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEOS="${THEOS:-$HOME/theos}"
FLEX_DEB="$ROOT/vendor/com.hopeless.autoflex_0.0.1_iphoneos-arm.deb"
# The bundle id is left alone by default, the way EeveeSpotify and the YouTube mods leave it. Rewriting
# it only works when it ends up equal to the App ID of the profile that signs the IPA, and this build
# has no idea what that profile will be -- it is picked later, in Feather or whatever else the person
# signing uses. A mismatched pair still installs, but MediaRemote launches the now playing app by its
# application-identifier entitlement, so tapping the lock screen card asks for a bundle that does not
# exist and nothing opens. Set BUNDLE_ID only if you know it matches your App ID; scripts/install.sh
# reads that App ID out of the profile and can do it safely.
BUNDLE_ID="${BUNDLE_ID:-}"
mkdir -p "$ROOT/out"

IN="" OUT="" WITH_FLEX=1 INSTALL=0 NAME="" ICON=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --icon) ICON="$2"; shift 2 ;;
    --no-flex) WITH_FLEX=0; shift ;;
    --install) INSTALL=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) IN="$1"; shift ;;
  esac
done
[ -n "$IN" ] || { echo "no IPA: put a decrypted Spotify .ipa in ipa/, or pass one (make build IPA=path.ipa)" >&2; exit 1; }
[ -f "$IN" ] || { echo "no such file: $IN" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing $1 -> $2" >&2; exit 1; }; }
need gmake "brew install make"
need ldid "brew install ldid"
need dpkg-deb "brew install dpkg"
need cyan "uv tool install 'cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw'"
{ ls -d "$THEOS"/sdks/iPhoneOS*.sdk "$(xcode-select -p 2>/dev/null)"/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk 2>/dev/null || true; } \
  | grep -qE 'iPhoneOS(2[6-9]|[3-9][0-9])\.' \
  || { echo "no iPhoneOS 26+ SDK: xcode-select an Xcode 26 or newer, or put the SDK in $THEOS/sdks" >&2; exit 1; }
# cyan skips -k with only a warning when its environment has no Pillow.
if [ -n "$ICON" ]; then
  [ -f "$ICON" ] || { echo "no such icon: $ICON" >&2; exit 1; }
  "$(dirname "$(readlink -f "$(command -v cyan)")")/python" -c 'import PIL' 2>/dev/null \
    || { echo "cyan has no Pillow for --icon -> uv tool install --force --with pillow 'cyan @ git+https://github.com/asdfzxcvbn/pyzule-rw'" >&2; exit 1; }
fi

APP_DIR="$(unzip -Z1 "$IN" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"
[ -n "$APP_DIR" ] || { echo "no Payload/*.app in $IN" >&2; exit 1; }
SPOTIFY_VERSION="$(unzip -p "$IN" "${APP_DIR}Info.plist" > "$ROOT/out/.info.plist" && plutil -extract CFBundleShortVersionString raw -o - "$ROOT/out/.info.plist")"
rm -f "$ROOT/out/.info.plist"
# The name carries the mod's version, not Spotify's: it is the one the About page shows and the one
# worth telling builds apart by. version.txt is read the way tweak/Makefile reads it, so a build from
# a fork left behind by a release is named for the version it really is.
MOD_VERSION="$(cat "$ROOT/version.txt" 2>/dev/null || true)"
: "${MOD_VERSION:=0.0.0}"
OUT="${OUT:-$ROOT/out/Sigma-$MOD_VERSION.ipa}"
echo "==> Sigma $MOD_VERSION on Spotify $SPOTIFY_VERSION -> $OUT"

# The flag table is generated rather than committed, so it always matches the IPA being built.
if [ ! -f "$ROOT/tweak/Sources/Shared/Flags/SGFlagList.m" ]; then
  echo "==> extracting the flag table (once, about 40 s)"
  "$ROOT/scripts/extract-flags.py" "$IN"
fi

echo "==> building tweak"
export THEOS
# Theos resolves its toolchain through `xcrun -sdk iphoneos`, which needs full Xcode. With only the
# Command Line Tools installed, name the tools directly instead.
if ! xcrun -sdk iphoneos --find clang >/dev/null 2>&1; then
  export TARGET_CC=clang TARGET_CXX=clang++ TARGET_LD=clang++ \
         TARGET_STRIP=strip TARGET_LIPO=lipo TARGET_CODESIGN_ALLOCATE=codesign_allocate TARGET_LIBTOOL=libtool
fi
# Theos builds its Swift support tools only at MAKELEVEL 0, and `make release` hands this script MAKELEVEL 1.
env -u MAKELEVEL gmake -C "$ROOT/tweak" clean package >/dev/null
TWEAK_DEB="$(ls -t "$ROOT"/tweak/packages/*.deb | head -1)"
echo "    $TWEAK_DEB"

FILES=("$TWEAK_DEB")
[ "$WITH_FLEX" = 1 ] && FILES+=("$FLEX_DEB")

# Spotify's widget reads what the app writes through App Group suites the re-signed IPA is not entitled
# to, and Siri reads the login from a keychain group it is not entitled to either; this dylib, loaded by
# the app and its extensions, puts them all on groups the signature does have.
echo "==> building the App Group shim"
GROUPS_DYLIB="$ROOT/out/SpotifyGlassAppGroups.dylib"
xcrun --sdk iphoneos clang -target arm64-apple-ios16.0 -dynamiclib -fobjc-arc -Os -framework Foundation -framework Security \
  -install_name @rpath/SpotifyGlassAppGroups.dylib -o "$GROUPS_DYLIB" "$ROOT/extension/AppGroups/AppGroups.m"
FILES+=("$GROUPS_DYLIB")

# The Live Activity (Shared/LiveActivity) draws in a widget extension of its own, which needs Xcode's Swift and its
# App Intents metadata processor. A failure leaves the IPA without it: Mod Settings > Live Activity then does nothing.
EXT_DIR=""
if xcrun --sdk iphoneos --find swiftc >/dev/null 2>&1; then
  echo "==> building the Live Activity extension"
  unzip -p "$IN" "${APP_DIR}Info.plist" > "$ROOT/out/.info.plist"
  if "$ROOT/scripts/build-extension.sh" "$ROOT/out/.info.plist" "$ROOT/out/extension"; then
    EXT_DIR="$ROOT/out/extension"
    FILES+=("$EXT_DIR/SpotifyGlassLiveActivity.appex")
  else
    echo "    the Live Activity extension failed: building without it"
  fi
  rm -f "$ROOT/out/.info.plist"
else
  echo "==> no Xcode selected: building without the Live Activity extension"
fi

echo "==> injecting"
# -w drops the Watch app: its companion-app key would still name com.spotify.client and block the install.
unzip -p "$IN" "${APP_DIR}Info.plist" > "$ROOT/out/.info.plist"
python3 "$ROOT/scripts/merge-local-network-plist.py" "$ROOT/out/.info.plist" \
  "$ROOT/plist/liquid-glass.plist" "$ROOT/out/.injection.plist"
rm -f "$ROOT/out/.info.plist"
cyan -i "$IN" -o "$OUT" -f "${FILES[@]}" -l "$ROOT/out/.injection.plist" ${BUNDLE_ID:+-b "$BUNDLE_ID"} ${NAME:+-n "$NAME"} ${ICON:+-k "$ICON"} -w -s --overwrite
rm -f "$ROOT/out/.injection.plist"

# The widget reads the App Group suites; Siri (IntentsExtension) and the notification service sign in
# with the credentials the app keeps in the keychain (extension/AppGroups/AppGroups.m, issue #60).
PATCH="$(mktemp -d)"
EXT_BINS=()
for EXT in WidgetExtension IntentsExtension NotificationServiceExtension; do
  echo "==> loading the App Group shim in $EXT"
  EXT_BIN="${APP_DIR}PlugIns/$EXT.appex/$EXT"
  if unzip -l "$OUT" "$EXT_BIN" >/dev/null 2>&1; then
    unzip -q "$OUT" "$EXT_BIN" -d "$PATCH"
    "$ROOT/scripts/insert-dylib.py" "$PATCH/$EXT_BIN" @rpath/SpotifyGlassAppGroups.dylib
    # Fakesigned again with its own entitlements, the way cyan -s left it, for TrollStore.
    ldid -e "$PATCH/$EXT_BIN" > "$PATCH/ents.plist"
    ldid -S"$PATCH/ents.plist" "$PATCH/$EXT_BIN"
    EXT_BINS+=("$EXT_BIN")
  else
    echo "    no $EXT.appex in this IPA"
  fi
done
# One zip pass: each update rewrites the whole IPA.
if [ ${#EXT_BINS[@]} -gt 0 ]; then
  OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
  (cd "$PATCH" && zip -q "$OUT_ABS" "${EXT_BINS[@]}")
fi
rm -rf "$PATCH"

echo "==> adding the alternate app icons"
# A failure leaves the IPA as it was, without them; Mod > App icon then does not show.
"$ROOT/scripts/app-icons.sh" "$OUT" || echo "    the app icons failed: building without them"

echo "==> making the launch screen plain"
# A failure leaves Spotify's launch screen.
"$ROOT/scripts/launch-screen.sh" "$OUT" || echo "    the launch screen failed: left as Spotify's"

if [ -n "$EXT_DIR" ]; then
  echo "==> adding the Live Activity's intents to Spotify's App Intents metadata"
  # A failure leaves the IPA as it was: the card shows, its taps do nothing.
  "$ROOT/scripts/merge-appintents.py" "$OUT" "$APP_DIR" "$EXT_DIR/app/Metadata.appintents" || echo "    the intents failed: the card's taps will not work"
fi

echo "==> done: $OUT"
[ "$INSTALL" = 1 ] && exec "$ROOT/scripts/install.sh" "$OUT"
exit 0
