#!/usr/bin/env bash
# Makes the IPA's launch screen plain: Spotify's has its logo in the middle, one picture for every app icon,
# and the mod shows the icon in use itself once the app is up (tweak/Sources/Shared/Splash).
#
#   scripts/launch-screen.sh <out.ipa>   (pipeline.sh runs it)
#
# A storyboard with only Spotify's launch grey is compiled with ibtool and put in place of the app's
# LaunchScreen.storyboardc. Without Xcode's ibtool the IPA is left as it was.
set -euo pipefail

OUT="$1"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
APP_DIR="$(unzip -Z1 "$OUT" | grep -oE '^Payload/[^/]+\.app/' | sort -u | head -1)"

skip() { echo "    $1: the launch screen is left as Spotify's"; exit 0; }
xcrun --find ibtool >/dev/null 2>&1 || skip "no ibtool"
unzip -Z1 "$OUT" | grep -q "^${APP_DIR}LaunchScreen.storyboardc/" || skip "no LaunchScreen.storyboardc in this IPA"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/LaunchScreen.storyboard" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="21701" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0" width="375" height="667"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <color key="backgroundColor" red="0.0706" green="0.0706" blue="0.0706" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
        </scene>
    </scenes>
</document>
XML

xcrun ibtool --errors --warnings --output-format human-readable-text \
  --compile "$WORK/app/${APP_DIR}LaunchScreen.storyboardc" "$WORK/LaunchScreen.storyboard" \
  --target-device iphone --target-device ipad --minimum-deployment-target 16.0 --platform iphoneos \
  > "$WORK/ibtool.log" 2>&1 || { cat "$WORK/ibtool.log" >&2; skip "ibtool failed"; }
[ -d "$WORK/app/${APP_DIR}LaunchScreen.storyboardc" ] || skip "ibtool wrote nothing"

zip -q -d "$OUT_ABS" "${APP_DIR}LaunchScreen.storyboardc/*" >/dev/null 2>&1 || true
(cd "$WORK/app" && zip -qr "$OUT_ABS" "${APP_DIR}LaunchScreen.storyboardc")
echo "    plain launch screen"
