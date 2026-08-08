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
