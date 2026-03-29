#!/bin/bash
set -euo pipefail

IMAGE_NAME="systems-test"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cd "$REPO_ROOT"

echo "Building test image..."
podman build -t "$IMAGE_NAME" -f tests/Containerfile .

_pass=0
_fail=0

run_test() {
    local name="$1"; shift
    echo ""
    echo "--- TEST: $name ---"
    if podman run --rm "$IMAGE_NAME" bash -c "$*"; then
        echo "--- PASS: $name ---"
        _pass=$((_pass + 1))
    else
        echo "--- FAIL: $name ---"
        _fail=$((_fail + 1))
    fi
}

# Profile loading (default.conf hostname is empty, no local.conf in container)
run_test "profile-load" \
    'source lib/config.sh && load_profile profiles && [[ -z "$(profile_get system hostname)" ]]'

# Profile validation — valid profile accepted
run_test "validate-profile-ok" '
    source lib/config.sh
    load_profile profiles
    validate_profile
'

# Profile validation — unknown key rejected
run_test "validate-profile-unknown-key" '
    source lib/config.sh
    load_profile profiles
    _CONFIG["system.typo_key"]="oops"
    output=$(validate_profile 2>&1) && exit 1
    echo "$output" | grep -q "Unknown profile key"
'

# Profile validation — bad boolean rejected
run_test "validate-profile-bad-boolean" '
    source lib/config.sh
    load_profile profiles
    _CONFIG["system.firewalld"]="yes"
    output=$(validate_profile 2>&1) && exit 1
    echo "$output" | grep -q "must be"
'

# Color presets
run_test "color-presets" '
    source lib/config.sh
    source lib/colors.sh
    REPO_ROOT=/systems load_all_presets
    [[ ${#COLOR_PRESETS[@]} -ge 3 ]]
    echo "Loaded ${#COLOR_PRESETS[@]} presets"
'

# Color accent loading
run_test "color-accent" '
    source lib/config.sh
    source lib/colors.sh
    load_profile profiles
    REPO_ROOT=/systems load_all_presets
    load_accent
    [[ "$ACCENT_NAME" == "green" ]]
    [[ "$ACCENT_PRIMARY" == "#88DD00" ]]
    echo "Accent: $ACCENT_NAME PRIMARY=$ACCENT_PRIMARY"
'

# Links library
run_test "links-check" '
    source lib/common.sh
    source lib/links.sh
    result=$(check_link "/nonexistent" "/tmp/test")
    [[ "$result" == "src_missing" ]]
    echo "check_link returned: $result"
'

# Setup help
run_test "setup-help" \
    './setup --help 2>&1 | grep -q "Usage:"'

# Setup status (limited — no systemd in container)
run_test "setup-status" \
    './setup status 2>&1 | grep -q "Profile:"'

# Theme --list
run_test "theme-list" '
    ./setup theme --list 2>&1 | grep -q "Active accent:"
'

# Theme --audit
run_test "theme-audit" '
    ./setup theme --audit 2>&1 | grep -q "Accent Color Audit"
'

# Packs mechanism
run_test "packs-devops" '
    source lib/common.sh
    source lib/config.sh
    load_profile profiles
    export PROFILE_APPS_PACKS="base devops"
    export REPO_ROOT=/systems
    source modules/apps.sh
    apps::init
    _apps_get_all_rpm_targets | grep -q kubectl
'

# Shellcheck
run_test "shellcheck" \
    'shellcheck setup modules/*.sh lib/*.sh'

echo ""
echo "========================================"
echo "Results: $_pass passed, $_fail failed"
echo "========================================"
[[ $_fail -eq 0 ]] || exit 1
