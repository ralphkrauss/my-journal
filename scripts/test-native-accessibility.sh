#!/bin/bash
# Exercise recovery at the largest Dynamic Type size in dark mode.
set -euo pipefail
cd "$(dirname "$0")/.."
simulator_id="$(scripts/prepare-simulator.sh)"
export JOURNAL_SIMULATOR_ID="$simulator_id"
original_appearance="$(xcrun simctl ui "$simulator_id" appearance)"
original_text_size="$(xcrun simctl ui "$simulator_id" content_size)"
case "$original_appearance" in light | dark) ;; *)
  echo "Simulator appearance is unavailable." >&2
  exit 1
  ;;
esac
case "$original_text_size" in unknown | unsupported | '')
  echo "Simulator text size is unavailable." >&2
  exit 1
  ;;
esac
restore_preferences() {
  local test_status=$?
  xcrun simctl ui "$simulator_id" appearance "$original_appearance" || test_status=1
  xcrun simctl ui "$simulator_id" content_size "$original_text_size" || test_status=1
  exit "$test_status"
}
trap restore_preferences EXIT
xcrun simctl ui "$simulator_id" appearance dark
xcrun simctl ui "$simulator_id" content_size accessibility-extra-extra-extra-large
# Reuse the disposable server so image editing is exercised with a synced attachment.
if [[ $# -eq 0 ]]; then
  set -- \
    -only-testing:JournalIOSUITests/JournalUITests/testDeleteLastJournalAndRestoreWithoutLosingEntry \
    -only-testing:JournalIOSUITests/JournalUITests/testPairDeviceAndDownloadEncryptedEntry \
    -only-testing:JournalIOSUITests/ConnectionSetupUITests/testSetUpEncryptedServerThenSignInOnAnotherDevice \
    -only-testing:JournalIOSUITests/ConnectionSetupUITests/testSetUpServerWithoutEncryptionThenAddAnotherDevice \
    -only-testing:JournalIOSUITests/HistoryUITests/testRestoreHistoricalEntryAndJournalSettingsThenReopen \
    -only-testing:JournalIOSUITests/ArchiveUITests/testArchiveWrongKeyRetryRestoreAndReopen \
    -only-testing:JournalIOSUITests/EntryActionsUITests/testFormattingAndDateActionsPreserveWritingAcrossRelaunch \
    -only-testing:JournalIOSUITests/WritingWorkflowUITests/testDefaultTemplateWritingScopedSearchAndRelaunchPreserveContent \
    -only-testing:JournalIOSUITests/EntryConflictUITests/testReviewRemoteImageCancelThenKeepBothAcrossRelaunch \
    -only-testing:JournalIOSUITests/PermanentDeletionUITests/testCancelThenPermanentlyDeleteEntryAndRelaunch \
    -only-testing:JournalIOSUITests/DeletionConflictUITests/testHiddenDeletionConflictKeepsCopyInChosenJournalAcrossRelaunch \
    -only-testing:JournalIOSUITests/DeletionConflictUITests/testKeepEntryPreservesIdentityInChosenJournalAcrossRelaunch \
    -only-testing:JournalIOSUITests/DeletionConflictUITests/testKeepJournalPreservesSettingsWithoutRevivingDeletedChildren \
    -only-testing:JournalIOSUITests/DeletionConflictUITests/testCancelThenKeepDeletionRemovesEditedConflictAndHistoryAcrossRelaunch \
    -only-testing:JournalIOSUITests/EntryParentRecoveryUITests/testCancelThenRestoreEntryAndJournalPreservingSiblingStatesAcrossRelaunch
fi
scripts/test-native-pairing.sh "$@"
