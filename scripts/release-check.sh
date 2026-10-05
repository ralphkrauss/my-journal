#!/bin/bash
# Checks the working tree before a TestFlight build and can then archive both apps from it
# (docs/engineering/release-checks.md). It runs the lanes that the changes since the last verified tree need, runs
# independent lanes side by side with at most one simulator lane at a time, and stops everything at the first failure.
#   mise exec -- scripts/release-check.sh [--plan] [--full] [--serial] [--base <commit>] [--lanes <a,b>]
#                                         [--archive <build-number>]
# --plan prints the lanes and why, without running them. --full runs every routine lane. --base compares with a commit
# instead of the last verified tree. --lanes runs exactly the named lanes and is not recorded as a verification.
# --serial runs one lane at a time. --archive also archives iOS and Mac into artifacts/testflight/{ios,mac}-<number>;
# it needs JOURNAL_SIGNING_TEAM, and JOURNAL_SIGNING_IDENTITY for a Mac archive that Xcode can distribute.
set -euo pipefail
cd "$(dirname "$0")/.."

routine_lanes=(hygiene lint backend audit core mac sync sync-health sync-efficiency server-recovery ios-ui recovery-ui)
known_lanes=" ${routine_lanes[*]} accessibility "
# A full run is due after this many days or selective runs since the last one.
full_after_days=7
full_after_runs=5
state_dir=artifacts/release-check
history="$state_dir/history.tsv"

plan_only=0
force_full=0
serial=0
base_arg=""
lanes_arg=""
build_number=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) plan_only=1 ;;
    --full) force_full=1 ;;
    --serial) serial=1 ;;
    --base)
      base_arg="${2:?--base needs a commit}"
      shift
      ;;
    --lanes)
      lanes_arg="${2:?--lanes needs a comma-separated list}"
      shift
      ;;
    --archive)
      build_number="${2:?--archive needs a build number}"
      shift
      ;;
    *)
      sed -n '5,11p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -n "$build_number" ]]; then
  [[ "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || {
    echo "The build number must be one to three period-separated integers." >&2
    exit 2
  }
  [[ -n "${JOURNAL_SIGNING_TEAM:-}" ]] || {
    echo "Set JOURNAL_SIGNING_TEAM to archive." >&2
    exit 2
  }
  for platform in ios mac; do
    [[ ! -e "artifacts/testflight/$platform-$build_number" ]] || {
      echo "artifacts/testflight/$platform-$build_number already exists; choose another build number." >&2
      exit 2
    }
  done
fi

# The tree being checked, including uncommitted and untracked files (not ignored ones), as a Git tree. It is compared
# with the last verified tree and again at the end, so results always describe one exact tree.
tree_fingerprint() {
  local index
  index="$(mktemp "${TMPDIR:-/tmp}/release-check-index.XXXXXX")"
  cp "$(git rev-parse --git-path index)" "$index"
  GIT_INDEX_FILE="$index" git add -A .
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

clock() {
  local seconds="$1"
  if ((seconds >= 3600)); then
    printf '%d:%02d:%02d' $((seconds / 3600)) $((seconds % 3600 / 60)) $((seconds % 60))
  else
    printf '%d:%02d' $((seconds / 60)) $((seconds % 60))
  fi
}

# --- Selection ------------------------------------------------------------------------------------------------------

selected=" "
full_reason=""
ui_all=0
ui_only=()

has_lane() { [[ "$selected" == *" $1 "* ]]; }

# Selects a lane and remembers the first reason for it.
select_lane() {
  local lane="$1" reason="$2"
  has_lane "$lane" && return 0
  selected+="$lane "
  printf -v "reason_${lane//-/_}" '%s' "$reason"
}

lane_reason() {
  local name="reason_${1//-/_}"
  printf '%s' "${!name:-}"
}

select_ui_all() {
  ui_all=1
  select_lane ios-ui "$1"
}

select_ui_tests() {
  local reason="$1" identifier existing
  shift
  select_lane ios-ui "$reason"
  for identifier in "$@"; do
    for existing in ${ui_only[@]+"${ui_only[@]}"}; do
      [[ "$existing" != "$identifier" ]] || continue 2
    done
    ui_only+=("$identifier")
  done
}

require_full() {
  [[ -n "$full_reason" ]] || full_reason="$1"
}

# A UI test file whose only shared declarations are test classes needs only those classes; other files can hold
# helpers that any test uses.
select_ui_test_file() {
  local path="$1" classes declarations class identifiers=()
  if [[ ! -f "$path" ]]; then
    select_ui_all "$path"
    select_lane recovery-ui "$path"
    return 0
  fi
  classes="$(sed -n -E 's/^(@[A-Za-z]+ +)*(final +)?class +([A-Za-z0-9_]+) *: *XCTestCase.*/\3/p' "$path")"
  declarations="$(grep -cE '^(@[A-Za-z]+ +)*((public|internal|final|nonisolated) +)*(extension|struct|enum|func|protocol|let|var|actor|typealias|class) ' "$path" || true)"
  if [[ -z "$classes" || "$declarations" -ne "$(grep -c . <<<"$classes")" ]]; then
    select_ui_all "$path"
    select_lane recovery-ui "$path"
    return 0
  fi
  for class in $classes; do
    if [[ "$class" == SyncRecoveryUITests ]]; then
      select_lane recovery-ui "$path"
    else
      identifiers+=("JournalIOSUITests/$class")
    fi
  done
  [[ ${#identifiers[@]} -eq 0 ]] || select_ui_tests "$path" "${identifiers[@]}"
}

# Maps a changed path to the lanes that cover it. Unknown paths need a full run.
classify() {
  local path="$1"
  case "$path" in
    *.swift) select_lane lint "$path" ;;
  esac
  case "$path" in
    scripts/release-check.sh) ;;
    protocol/* | mise.toml | mise.lock | global.json)
      require_full "$path"
      ;;
    apps/apple/Packages/JournalCore/Sources/JournalProbe/*)
      select_lane core "$path"
      select_lane sync "$path"
      select_lane sync-health "$path"
      select_lane sync-efficiency "$path"
      ;;
    apps/apple/Packages/JournalCore/Sources/JournalMeasure/* | apps/apple/Packages/JournalCore/Tests/*)
      select_lane core "$path"
      ;;
    apps/apple/Packages/JournalCore/*)
      require_full "$path"
      ;;
    server/Dockerfile) ;;
    server/tests/*) select_lane backend "$path" ;;
    server/* | Directory.Build.props | .editorconfig | dotnet-tools.json)
      select_lane backend "$path"
      select_lane sync "$path"
      select_lane sync-health "$path"
      select_lane sync-efficiency "$path"
      select_lane server-recovery "$path"
      select_lane recovery-ui "$path"
      # The UI tests that use a disposable server: pairing, setting one up, agent access and merging.
      select_ui_tests "$path" JournalIOSUITests/JournalUITests/testPairDeviceAndDownloadEncryptedEntry \
        JournalIOSUITests/ConnectionSetupUITests JournalIOSUITests/AgentAccessUITests JournalIOSUITests/MergeUITests
      ;;
    apps/apple/JournalApp/Views/Mac/* | apps/apple/MacResources/* | apps/apple/JournalServerTests/* | apps/apple/Signing/*)
      select_lane mac "$path"
      select_lane server-recovery "$path"
      ;;
    apps/apple/JournalTests/*)
      select_lane mac "$path"
      select_ui_tests "$path" JournalIOSTests
      ;;
    apps/apple/JournalUITests/*)
      select_ui_test_file "$path"
      ;;
    apps/apple/JournalApp/* | apps/apple/project.yml | scripts/generate-apple.sh)
      select_lane mac "$path"
      select_lane server-recovery "$path"
      select_lane recovery-ui "$path"
      select_ui_all "$path"
      ;;
    .swift-format | .swiftlint.yml) select_lane lint "$path" ;;
    scripts/check.sh)
      for lane in lint backend core mac; do select_lane "$lane" "$path"; done
      ;;
    scripts/test-sync.sh) select_lane sync "$path" ;;
    scripts/test-sync-health.sh) select_lane sync-health "$path" ;;
    scripts/test-sync-efficiency.sh | scripts/sync-fault-proxy.py) select_lane sync-efficiency "$path" ;;
    scripts/test-server-recovery.sh) select_lane server-recovery "$path" ;;
    scripts/test-native-pairing.sh) select_ui_all "$path" ;;
    scripts/test-sync-recovery-ui.sh) select_lane recovery-ui "$path" ;;
    scripts/test-native-accessibility.sh) select_lane accessibility "$path" ;;
    # Opt-in checks that releases don't run.
    scripts/test-native-file-import.sh | scripts/test-mac-sandbox.sh | scripts/test-packaged-container.sh | \
      scripts/test-server-image.sh | scripts/test-https-deployment.py | scripts/test-packaged-server.py) ;;
    # A new test lane needs a rule above.
    scripts/test-*) require_full "$path" ;;
    scripts/package-server.sh | packaging/*)
      select_lane sync-health "$path"
      select_lane server-recovery "$path"
      select_lane recovery-ui "$path"
      ;;
    scripts/prepare-simulator.sh | scripts/verify-test-results.py)
      select_lane server-recovery "$path"
      select_lane recovery-ui "$path"
      select_ui_all "$path"
      ;;
    # Opt-in lanes that releases don't run (Files acceptance, measurements, screenshots, sandbox) and files that only
    # the hygiene lane checks. Archiving builds the apps either way.
    apps/apple/JournalFileTests/* | apps/apple/JournalMeasurements/* | apps/apple/JournalScreenshots/* | \
      apps/apple/JournalSandboxTests/* | apps/apple/*.yml) ;;
    scripts/* | .github/* | .githooks/* | docs/* | design/* | deploy/* | *.md | LICENSE | NOTICE | .git* | \
      .dockerignore | ruff.toml) ;;
    *) require_full "$path" ;;
  esac
}

head_commit="$(git rev-parse HEAD)"
current_tree="$(tree_fingerprint)"
xcode_version="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
build_commit="$(git log -1 -E --grep='^Build [0-9]+' --format=%H)"

# The last verified tree and the last full run, from this Mac's history (time, tree, commit, scope, Xcode).
last_tree="" last_full_time="" last_full_xcode="" runs_since_full=0
if [[ -f "$history" ]]; then
  while IFS=$'\t' read -r recorded tree _ scope xcode; do
    last_tree="$tree"
    if [[ "$scope" == full ]]; then
      last_full_time="$recorded"
      last_full_xcode="$xcode"
      runs_since_full=0
    else
      runs_since_full=$((runs_since_full + 1))
    fi
  done <"$history"
fi
# Before the first recorded run, each build commit went through every lane.
if [[ -z "$last_full_time" && -n "$build_commit" ]]; then
  last_full_time="$(git log -1 --format=%ct "$build_commit")"
fi

base="" base_description=""
if [[ -n "$base_arg" ]]; then
  base="$(git rev-parse --verify "$base_arg^{tree}")"
  base_description="$base_arg"
elif [[ -n "$last_tree" ]] && git cat-file -e "$last_tree^{tree}" 2>/dev/null; then
  base="$last_tree"
  base_description="the last verified tree"
elif [[ -n "$build_commit" ]]; then
  base="$build_commit"
  base_description="$(git log -1 --format='%h "%s"' "$build_commit")"
fi

changed=()
if [[ -n "$lanes_arg" ]]; then
  for lane in ${lanes_arg//,/ }; do
    [[ "$known_lanes" == *" $lane "* ]] || {
      echo "Unknown lane: $lane. Lanes:$known_lanes" >&2
      exit 2
    }
    select_lane "$lane" "requested"
  done
  if has_lane ios-ui; then ui_all=1; fi
else
  now="$(date +%s)"
  if ((force_full)); then
    require_full "requested with --full"
  elif [[ -z "$base" ]]; then
    require_full "no verified tree or build commit to compare with"
  elif [[ -z "$last_full_time" ]]; then
    require_full "no full run recorded"
  elif ((now - last_full_time > full_after_days * 86400)); then
    require_full "the last full run was $(((now - last_full_time) / 86400)) days ago"
  elif ((runs_since_full >= full_after_runs)); then
    require_full "$runs_since_full selective runs since the last full run"
  elif [[ -n "$last_full_xcode" && "$last_full_xcode" != "$xcode_version" ]]; then
    require_full "Xcode changed since the last full run ($last_full_xcode)"
  fi
  if [[ -n "$base" ]]; then
    while IFS= read -r path; do
      changed+=("$path")
    done < <(git diff --no-renames --name-only "$base" "$current_tree")
  fi
  for path in ${changed[@]+"${changed[@]}"}; do
    classify "$path"
  done
  if [[ -n "$full_reason" ]]; then
    ui_all=1
    for lane in "${routine_lanes[@]}"; do select_lane "$lane" "full run: $full_reason"; done
  fi
  select_lane hygiene "always: secret scan, scripts and release guards"
  select_lane audit "always: advisories appear without changes"
fi

ui_args=()
if has_lane ios-ui && ((ui_all == 0)); then
  for identifier in "${ui_only[@]}"; do ui_args+=("-only-testing:$identifier"); done
fi

print_plan() {
  local lane label skipped=""
  if [[ -n "$lanes_arg" ]]; then
    echo "Lanes chosen with --lanes; this run is not recorded as a verification."
  else
    printf 'Changes since %s: %d files.\n' "${base_description:-nothing}" "${#changed[@]}"
    [[ -z "$full_reason" ]] || printf 'Full run: %s.\n' "$full_reason"
  fi
  for lane in "${routine_lanes[@]}" accessibility; do
    if has_lane "$lane"; then
      label="$lane"
      if [[ "$lane" == ios-ui ]]; then
        if ((ui_all)); then label="ios-ui (all)"; else label="ios-ui (${#ui_args[@]} selected)"; fi
      fi
      printf '  %-22s %s\n' "$label" "$(lane_reason "$lane")"
    elif [[ "$lane" != accessibility ]]; then
      skipped+=" $lane"
    fi
  done
  for identifier in ${ui_args[@]+"${ui_args[@]}"}; do printf '    %s\n' "$identifier"; done
  [[ -z "$skipped" ]] || printf 'Not needed:%s\n' "$skipped"
  [[ -z "$build_number" ]] || printf 'Then archive build %s for iOS and Mac.\n' "$build_number"
}
print_plan
((plan_only == 0)) || exit 0

# --- Running --------------------------------------------------------------------------------------------------------

run="$state_dir/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run/logs" "$run/results"
run_started="$(date +%s)"
package="$run/server"

say() {
  printf '%7s  %s\n' "$(clock $(($(date +%s) - run_started)))" "$*"
}

lane_command() {
  case "$1" in
    hygiene | lint | backend | audit | core) scripts/check.sh "$1" ;;
    # Its own derived data, so it builds beside the lanes that use artifacts/DerivedData.
    mac) JOURNAL_DERIVED_DATA=artifacts/DerivedDataMacTests scripts/check.sh mac ;;
    generate) scripts/generate-apple.sh ;;
    # One published server for the lanes that accept it.
    package) scripts/package-server.sh osx-arm64 "$package" ;;
    sync) JOURNAL_TEST_RESULTS="$run/results/sync" scripts/test-sync.sh ;;
    sync-health) JOURNAL_SERVER_PACKAGE="$package" JOURNAL_TEST_RESULTS="$run/results/sync-health" scripts/test-sync-health.sh ;;
    sync-efficiency) JOURNAL_TEST_RESULTS="$run/results/sync-efficiency" scripts/test-sync-efficiency.sh ;;
    server-recovery) JOURNAL_TEST_RESULTS="$run/results/server-recovery" scripts/test-server-recovery.sh ;;
    ios-ui) JOURNAL_TEST_RESULTS="$run/results/ios-ui" scripts/test-native-pairing.sh ${ui_args[@]+"${ui_args[@]}"} ;;
    recovery-ui)
      JOURNAL_SERVER_PACKAGE="$package" JOURNAL_TEST_RESULTS="$run/results/recovery-ui" scripts/test-sync-recovery-ui.sh
      ;;
    accessibility) JOURNAL_TEST_RESULTS="$run/results/accessibility" scripts/test-native-accessibility.sh ;;
    # The archive scripts' derived data is only needed while they build.
    archive-ios)
      JOURNAL_BUILD_NUMBER="$build_number" scripts/archive-ios.sh "artifacts/testflight/ios-$build_number" &&
        rm -rf "artifacts/testflight/ios-$build_number/build"
      ;;
    archive-mac)
      JOURNAL_BUILD_NUMBER="$build_number" scripts/archive-mac.sh "artifacts/testflight/mac-$build_number" &&
        rm -rf "artifacts/testflight/mac-$build_number/build"
      ;;
  esac
}

run_lane() {
  local lane="$1" started status=0 took
  # These pick servers' ports from the fixed loopback range 18950-18959 when they start, and sync-health restarts its
  # servers on the ports it picked, so another lane could take one in between. They never overlap with sync-health.
  if [[ "$lane" == recovery-ui || "$lane" == server-recovery ]] && has_lane sync-health; then
    while [[ ! -e "$run/passed-sync-health" ]]; do
      [[ ! -e "$run/failed" ]] || return 1
      sleep 2
    done
  fi
  started="$(date +%s)"
  say "start   $lane"
  lane_command "$lane" </dev/null >"$run/logs/$lane.log" 2>&1 || status=$?
  took=$(($(date +%s) - started))
  printf '%s\t%s\t%s\n' "$lane" "$status" "$took" >>"$run/lanes.tsv"
  if ((status == 0)); then
    touch "$run/passed-$lane"
    say "passed  $lane ($(clock "$took"))"
  else
    touch "$run/failed"
    say "FAILED  $lane ($(clock "$took")), exit $status. Log: $run/logs/$lane.log"
  fi
  return "$status"
}

# Runs lanes one after another, stopping at a failure, then marks the track done.
run_track() {
  local track="$1" lane
  shift
  for lane in "$@"; do
    run_lane "$lane" || return 1
  done
  touch "$run/done-$track"
}

track_pids=()

start_track() {
  local track="$1"
  shift
  [[ $# -gt 0 ]] || {
    touch "$run/done-$track"
    return 0
  }
  if ((serial)); then
    run_track "$track" "$@" || fail 1
  else
    # Its own process group, so a failure elsewhere can stop the whole track.
    set -m
    run_track "$track" "$@" &
    track_pids+=("$!")
    set +m
  fi
}

# Interrupts every running track's process group as Control-C would, so lane scripts stop their servers and restore
# simulator settings, and escalates if a track doesn't stop.
stop_tracks() {
  local pid signal attempt
  for signal in INT TERM KILL; do
    for pid in ${track_pids[@]+"${track_pids[@]}"}; do
      [[ -z "$pid" ]] || kill -s "$signal" -- "-$pid" 2>/dev/null || true
    done
    for attempt in {1..30}; do
      local alive=0
      for pid in ${track_pids[@]+"${track_pids[@]}"}; do
        [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null || alive=1
      done
      ((alive)) || break
      if ((attempt < 30)); then sleep 1; fi
    done
    ((alive)) || break
  done
  for pid in ${track_pids[@]+"${track_pids[@]}"}; do
    [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
  done
  track_pids=()
}

# Stops the lanes, removes what only this run needed and prints the timings.
finish() {
  local status="$1"
  finished=1
  trap - INT TERM
  ((serial)) || stop_tracks
  rm -rf "$package"
  if ((status == 0)); then
    rm -rf "$run/results"
  fi
  if [[ -f "$run/lanes.tsv" ]]; then
    local lane lane_status took total=0
    printf '\n%-18s %-8s %s\n' Lane Result Time
    while IFS=$'\t' read -r lane lane_status took; do
      if ((lane_status == 0)); then lane_status=passed; else lane_status=FAILED; fi
      printf '%-18s %-8s %s\n' "$lane" "$lane_status" "$(clock "$took")"
      total=$((total + took))
    done <"$run/lanes.tsv"
    printf 'Took %s; the same lanes one after another took %s. Logs: %s\n' \
      "$(clock $(($(date +%s) - run_started)))" "$(clock "$total")" "$run"
  fi
  # Keep the five newest runs' logs.
  find "$state_dir/runs" -mindepth 1 -maxdepth 1 -type d | sort -r | tail -n +6 | while IFS= read -r old; do
    rm -rf "$old"
  done
}

fail() {
  finish "$1"
  exit "$1"
}

finished=0
# Unexpected errors still stop the lanes and remove the published server.
on_exit() {
  if ((finished == 0)); then
    stop_tracks
    rm -rf "$package"
  fi
}
on_interrupt() {
  say "Interrupted; stopping lanes."
  touch "$run/failed"
  fail 130
}
trap on_exit EXIT
trap on_interrupt INT TERM

# Waits for the running tracks. Starts the archive track once the iOS UI lane and the host lanes have passed, so it
# overlaps the last simulator lane. Stops everything at the first failure.
wait_tracks() {
  local index pid status running
  while :; do
    running=0
    for index in ${track_pids[@]+"${!track_pids[@]}"}; do
      pid="${track_pids[$index]}"
      [[ -n "$pid" ]] || continue
      if kill -0 "$pid" 2>/dev/null; then
        running=1
        continue
      fi
      status=0
      wait "$pid" || status=$?
      track_pids[index]=""
      if ((status != 0)); then
        fail 1
      fi
    done
    if ((archive_pending)) && [[ -e "$run/done-host" ]] && { ! has_lane ios-ui || [[ -e "$run/passed-ios-ui" ]]; }; then
      archive_pending=0
      start_track archive archive-ios archive-mac
      running=1
    fi
    ((running)) || return 0
    sleep 2
  done
}

# Lanes in a selected order: cheap and likely failures first, simulator lanes one at a time.
ordered() {
  local lane
  for lane in "$@"; do
    if has_lane "$lane"; then printf '%s\n' "$lane"; fi
  done
}

lanes_of() {
  local lane result=()
  while IFS= read -r lane; do result+=("$lane"); done < <(ordered "$@")
  printf '%s ' ${result[@]+"${result[@]}"}
}

needs_project=0
for lane in mac server-recovery ios-ui recovery-ui accessibility; do
  if has_lane "$lane"; then needs_project=1; fi
done
[[ -z "$build_number" ]] || needs_project=1
gate_a="$(lanes_of hygiene lint)"
((needs_project == 0)) || gate_a+="generate "
gate_b="$(lanes_of backend)"
if has_lane sync-health || has_lane recovery-ui; then gate_b+="package "; fi
host="$(lanes_of sync-health sync core mac sync-efficiency audit)"
sim="$(lanes_of server-recovery ios-ui recovery-ui accessibility)"
archive_pending=0
[[ -z "$build_number" ]] || archive_pending=1

say "Release check of tree ${current_tree:0:12} (HEAD ${head_commit:0:12}). Logs: $run"
# shellcheck disable=SC2086 # The lane lists are single words.
{
  start_track gate-a $gate_a
  start_track gate-b $gate_b
  ((serial)) || wait_tracks
  start_track host $host
  start_track sim $sim
  if ((serial)); then
    if ((archive_pending)); then start_track archive archive-ios archive-mac; fi
  else
    wait_tracks
  fi
}

final_tree="$(tree_fingerprint)"
if [[ "$final_tree" != "$current_tree" ]]; then
  say "FAILED  The sources changed during the run, so these results don't describe one tree. Run it again."
  git diff --no-renames --name-only "$current_tree" "$final_tree" | head -10 | sed 's/^/         /'
  fail 1
fi
if [[ -z "$lanes_arg" ]]; then
  scope=selected
  [[ -z "$full_reason" ]] || scope=full
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$current_tree" "$head_commit" "$scope" "$xcode_version" >>"$history"
fi
say "All lanes passed."
[[ -z "$build_number" ]] || say "Archives: artifacts/testflight/ios-$build_number and artifacts/testflight/mac-$build_number"
finish 0
