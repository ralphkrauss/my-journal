# Unlock when the device key is unavailable

## Reproduced problem

A configured PIN survives loss of the Keychain master key. AppModel.load correctly leaves the app locked and explains recovery. However unlock(pin:) accepts the correct PIN, sets locked=false, clears the error and refreshes a nil store. This presents an empty-looking app instead of the recovery route. MissingDeviceKeyTests reproduces this with a synthetic absent Keychain account and exact existing entry; recovery afterwards works.

## Proposed behavior

Before PIN derivation or a biometric prompt, require both the master key and an opened store. If the master key is absent, keep the app locked and retain the existing copy: “Your device key is unavailable. Use your recovery key to unlock your journals.” Keep the secure field, Unlock button and Use Recovery Key action in the reviewed lock layout. Entering another PIN must not navigate away or hide recovery guidance. Recovery continues to restore the key, open the existing store and clear the device PIN, as currently designed.

If a key was loaded but opening the store failed, keep the app locked and preserve the load error. If no error was recorded, use “Your journals couldn’t be opened. Quit and reopen Journal.” Do not claim a key is missing in that case or create a replacement store implicitly through PIN/biometric unlock.

No new controls, authentication steps or layout changes. No biometric prompt when data cannot be opened. Native text sizing and scroll behavior remain unchanged. Normal available-vault PIN/biometric behavior remains unchanged.

## Verification

Focused model regression: missing key plus correct PIN stays locked with recovery guidance; recovery then restores the exact entry and clears the PIN. Native fixture with a configured PIN and missing key verifies actual error/action presentation and recovery at normal/largest text sizes. Independent source and actual UI inspection follow. Existing lock-flow native evidence is retained for normal available-key behavior; relevant Apple/hygiene checks run after edits, packages refreshed before delivery. Real biometric authentication and live Mac/VoiceOver remain environment-dependent.

## Authentication lifetime

Preflight also rejects a cancelled task or vault replacement. Capture the open store identity and vault session before PIN derivation/biometric authentication. Immediately after the await and in catch, require an uncancelled task, no replacement, the same store/session, and the captured authentication configuration still current before publishing success or an error. PIN checks retain the same salt/hash; biometric checks retain enabled biometrics. Stale completion returns quietly and cannot clear a newer lock/error. Use an authentication-specific check because the export validator correctly requires an already-unlocked vault. This change is bounded to PIN/biometric unlock; recovery itself is unchanged.

## Existing-vault load ordering

Source review also found store construction can throw before the current load() assigns locked from configuration. After decoding an existing configuration, set locked=true before reading Keychain or opening the store. Only the existing successful-load path may apply the configured PIN state and display entries. On failure retain the locked view and the real load error. This prevents a failed existing-vault open from resembling an empty journal. No new-vault behavior changes. A synthetic file occupying the configured storage-directory path reproduces this separately from missing-key handling.
