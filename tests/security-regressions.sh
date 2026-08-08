#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "security regression: $*" >&2
  exit 1
}

bash -n build.sh grant.sh install.sh uninstall.sh

while IFS= read -r ref; do
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]] || fail "GitHub Action is not pinned to a full commit SHA: $ref"
done < <(sed -n 's/^[[:space:]]*- uses: .*@\([^ #]*\).*/\1/p' .github/workflows/*.yml)

# shellcheck disable=SC2016 # GitHub expression is intentionally matched literally.
grep -Fq 'ref: ${{ steps.ver.outputs.tag }}' .github/workflows/release.yml \
  || fail "release checkout is not pinned to the resolved tag"
grep -Fq 'persist-credentials: false' .github/workflows/release.yml \
  || fail "release checkout persists credentials"
if grep -Fq -- '--clobber' .github/workflows/release.yml; then
  fail "release assets can be overwritten"
fi

grep -Fq 'applicationShouldTerminate' App.swift \
  || fail "normal app termination does not restore sleep"
grep -Fq 'turnOffForSafety' App.swift \
  || fail "automatic cutoffs do not share checked failure handling"
grep -Fq 'NSStatusItem.squareLength' App.swift \
  || fail "menu-bar icon does not use a fixed square slot"
grep -Fq 'case indeterminate' App.swift \
  || fail "battery parsing has no explicit indeterminate state"
grep -Fq 'env["LC_ALL"] = "C"' App.swift \
  || fail "pmset and sudo output parsing is locale-dependent"
grep -Fq 'case .failed(let detail)' App.swift \
  || fail "toggle failures are not surfaced"

# Lid-close display power saving must remain event-driven and scoped. With no external
# display, Apple's unprivileged pmset action may sleep all (there is only the built-in
# panel). With an external display, only the cached built-in panel may be dimmed.
grep -Fq 'com.apple.system.powermanagement.clamshellstate' App.swift \
  || fail "lid-close display saving does not use the clamshell notification"
grep -Fq 'runCommand("/usr/bin/pmset", ["displaysleepnow"])' App.swift \
  || fail "built-in-only display sleep does not use the exact unprivileged pmset command"
grep -Fq 'CGDisplayIsBuiltin' App.swift \
  || fail "display policy cannot distinguish the built-in panel from external displays"
grep -Fq 'DisplayServicesSetBrightness' App.swift \
  || fail "external-display policy cannot dim only the built-in panel"
grep -Fq '/System/Library/PrivateFrameworks/DisplayServices.framework' App.swift \
  || fail "private brightness symbols are not resolved from Apple's fixed system path"
grep -Fq 'savedBuiltInBrightnessKey' App.swift \
  || fail "built-in brightness is not persisted for crash recovery"
grep -Fq 'CFPreferencesAppSynchronize' App.swift \
  || fail "brightness recovery state is not flushed before changing hardware state"
grep -Fq 'restoreSavedBuiltInBrightness' App.swift \
  || fail "built-in brightness has no restoration path"
recovery_line="$(grep -n 'guard persistSavedBuiltInBrightness' App.swift | head -n1 | cut -d: -f1)"
dim_line="$(grep -n 'guard controller.write(0' App.swift | head -n1 | cut -d: -f1)"
[[ -n "$recovery_line" && -n "$dim_line" && "$recovery_line" -lt "$dim_line" ]] \
  || fail "built-in brightness changes before crash-recovery state is persisted"
if grep -Fq 'runPrivileged(["-n", "/usr/bin/pmset", "displaysleepnow"' App.swift; then
  fail "display sleep unnecessarily crosses the sudo boundary"
fi
if grep -Fq -- '-framework DisplayServices' build.sh; then
  fail "build links directly against Apple's private DisplayServices framework"
fi
grep -Fq 'sleepAllDisplaysOnLidClose' App.swift \
  || fail "all-display lid-close preference is missing"
grep -Fq 'Sleep external displays too' App.swift \
  || fail "all-display lid-close preference has no visible toggle"
grep -Fq 'prepareBuiltInDisplayForClosedLid' App.swift \
  || fail "built-in brightness is not prepared before a display-sleep request"
if grep -Eq '\.(keyDown|keyUp|mouseMoved|flagsChanged)' App.swift; then
  fail "lid-close display saving captures global keyboard or pointer activity"
fi

# shellcheck disable=SC2016 # Installer source is intentionally matched literally.
if grep -Fq 'launchctl bootstrap' install.sh || grep -Fq 'cat > "$LAUNCH_AGENT"' install.sh; then
  fail "installer still creates a second launch-at-login source"
fi

grep -Fq '*[!A-Za-z0-9._-]*' grant.sh \
  || fail "sudoers username is not constrained before interpolation"
grep -Fq '/usr/sbin/visudo' grant.sh \
  || fail "privileged validation does not use an absolute system path"
grep -Fq 'missing required sudoers template' grant.sh \
  || fail "grant installer does not fail closed when its template is missing"
# shellcheck disable=SC2016 # Bundle-copy source is intentionally matched literally.
grep -Fq 'sleepless.sudoers.template" "$CONTENTS/Resources/' build.sh \
  || fail "app bundle does not include the sudoers source-of-truth template"
if grep -Fq 'NOPASSWD: /usr/bin/pmset' grant.sh install.sh; then
  fail "sudoers command is duplicated outside its template"
fi
if SLEEPLESS_USER=$'attacker\nALL ALL=(ALL) NOPASSWD: ALL' bash grant.sh --yes >/dev/null 2>&1; then
  fail "grant installer accepted a sudoers username injection"
fi
if SLEEPLESS_USER=root bash grant.sh --yes >/dev/null 2>&1; then
  fail "grant installer accepted the root account"
fi

echo "security regression checks passed"
