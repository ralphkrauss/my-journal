#!/bin/bash
# Boot the simulator used by the native UI scripts and print its identifier.
# JOURNAL_SIMULATOR_ID selects an existing simulator. Otherwise a dedicated iPhone 17 simulator that holds only
# disposable test data is reused or created for the iOS runtime matching the selected Xcode's simulator SDK.
set -euo pipefail
name='Journal Test iPhone 17'
device_type=com.apple.CoreSimulator.SimDeviceType.iPhone-17
udid="${JOURNAL_SIMULATOR_ID:-}"
if [[ -z "$udid" ]]; then
  sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
  selection="$(
    xcrun simctl list -j devices runtimes | python3 -c '
import json
import sys

sdk, name, device_type = sys.argv[1:]
listing = json.load(sys.stdin)
runtimes = [
    runtime
    for runtime in listing["runtimes"]
    if runtime.get("platform") == "iOS"
    and runtime.get("isAvailable")
    and runtime.get("version", "").split(".")[:2] == sdk.split(".")[:2]
    and any(item["identifier"] == device_type for item in runtime.get("supportedDeviceTypes", []))
]
if not runtimes:
    raise SystemExit(f"Install the iOS {sdk} simulator runtime for the selected Xcode.")
runtime = max(runtimes, key=lambda item: item.get("buildversion", ""))["identifier"]
existing = [
    device["udid"]
    for device in listing["devices"].get(runtime, [])
    if device["name"] == name and device.get("isAvailable")
]
print(runtime, existing[0] if existing else "")
' "$sdk_version" "$name" "$device_type"
  )"
  runtime="${selection%% *}"
  udid="${selection#* }"
  if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl create "$name" "$device_type" "$runtime")"
  fi
fi
xcrun simctl bootstatus "$udid" -b >&2
# A fresh simulator shows one-time keyboard tips on first text entry, which can take a UI test's first taps.
# DidShowContinuousPathIntroduction is the slide-to-type tip (also preset by Appium's simulator setup);
# MultilingualKeyboardTip is the multilingual typing tip, recorded by iOS 26.5 once that tip is dismissed.
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences MultilingualKeyboardTip -bool true
printf '%s\n' "$udid"
