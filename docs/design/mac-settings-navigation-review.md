# macOS Settings navigation: bounded investigation

## Independent observations

Selected the exact isolated `artifacts/mac-input-acceptance/Journal Acceptance.app` through CUA. Its Sync Settings window showed the Server section with local-device copy and server setup actions. The actual screenshot showed Sync, Devices, Privacy, and Journals labels tightly abutting in a compact toolbar group beside Done.

The returned AX tree represented each tab-like item as a container with text/image children and toolbar movement/removal actions, without an exposed press/select action or selected-tab role. Direct screenshot-coordinate clicks on Privacy and Journals icons each left Sync/content/window focus unchanged. One alternate Control-F5 attempt also left the tree and window focus unchanged. No setting was toggled, form submitted, menu opened, access granted, or fixture modified. The reviewer left the window intact and handed control back to the parent.

These observations reproduce failed CUA navigation for the Settings scene, not confirmed physical mouse or keyboard failure. Inactive-window/event delivery and accessibility representation remain possible explanations. The parent subsequently confirmed the source uses standard TabView/tabItem Label in the Settings scene, rather than custom navigation buttons; this source finding was parent-reported and was not independently reviewed during the UI investigation. No production change is justified solely by the failed automation route.

## Parent-reported discriminating evidence

After the independent inspection, the parent reports closing Settings with the native close control successfully, then opening Manage Journals from the main sidebar. The same SettingsView presented as a sheet exposed actual AX tabs for Sync, Devices, Privacy, and Journals. Clicking Privacy immediately succeeded and displayed Agent Access. The parent continued isolated agent onboarding through that sheet. These later actions were not performed or watched by this reviewer.

This narrows the observed automation problem to the Settings scene's toolbar representation; it is evidence against a general TabView selection or Privacy-content failure. The sheet route is usable according to the parent's direct check. It does not establish whether a human physical click on the Settings toolbar fails, or whether the scene has a product defect versus an automation/AX limitation.

## Disposition

No production/UI correction proposed or approved from this evidence alone. Preserve the standard native navigation and use the demonstrated sheet route for the current bounded onboarding task. If the Settings scene issue is pursued, obtain a focused native/manual navigation observation before choosing an implementation change; retain the directly observed crowded labels and limited AX semantics as investigation notes. Do not describe Settings navigation as globally broken or globally accepted. No reviewer tests were rerun and no production code was changed.
