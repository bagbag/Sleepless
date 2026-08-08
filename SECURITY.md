# Security Policy

Sleepless asks for a narrow piece of root privilege, so it owes you a precise account
of what that privilege is and why it is safe. This document is that account. Nothing
here is hand-waved; every claim is something you can verify on your own machine.

## Reporting a vulnerability

If you find a security issue, please **do not open a public issue**. Email
**boudjemaa.adam@gmail.com** with details and steps to reproduce. You'll get an
acknowledgement within a few days. Coordinated disclosure is appreciated.

Supported version: the latest release on the `main` branch.

## What Sleepless actually does

Sleepless keeps a Mac awake with the lid closed by toggling an undocumented but
long-standing `pmset` setting:

```
sudo pmset -a disablesleep 1   # keep awake, even lid-closed
sudo pmset -a disablesleep 0   # restore normal sleep
```

`disablesleep` is **not** in Apple's `pmset(1)` man page (check: `man pmset`), but it
sets the kernel's `SleepDisabled` flag, which you can observe yourself:

```
pmset -g | grep SleepDisabled   # 1 = on, 0/absent = off
```

Because it is undocumented, Apple could change or remove it in a future macOS. Sleepless
reads the live value back after every toggle, so the menu-bar state always reflects
reality rather than assuming the command worked.

## The passwordless grant — exactly what it permits

A GUI app has no terminal to type a password into, so Sleepless runs `pmset` through a
tightly scoped `/etc/sudoers.d` drop-in. `install.sh` writes this (with your username
substituted for `__USER__`), owned `root:wheel`, mode `0440`:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

That line comes from `sleepless.sudoers.template`, which is bundled beside `grant.sh`.
The installer previews the generated template, and `grant.sh` refuses to continue if the
template is missing; there is no second executable copy that can drift from what is shown.

**This grant lets one user run, as root, exactly two fully-specified commands and nothing
else.** sudoers matches command arguments *literally* — and this rule contains **no
wildcards** — so the match is total. From the sudoers manual: *"If a Cmnd has associated
command line arguments, then the arguments in the Cmnd must match exactly those given by
the user on the command line (or match the wildcards if there are any)."*

Consequences you can rely on:

- `sudo pmset -a sleep 0`, `sudo pmset restoredefaults`, `sudo pmset -a hibernatemode 0`,
  or any other argument vector **do not match** the rule and will demand a password. The
  grant cannot be widened by appending flags.
- Sleepless calls `sudo` with an **argv array**, not a shell string
  (`Process.arguments` in `App.swift`), so there is no `/bin/sh -c`, no command
  substitution, and no word-splitting surface inside the app.
- There is **no helper script in the passwordless rule**. The classic sudoers footgun is a
  *user-writable* script that root can execute without authentication — rewrite it, get root.
  Sleepless points the rule directly at Apple's `/usr/bin/pmset`, and the sudoers file itself
  is `root:wheel 0440` (you cannot modify it without `sudo`). The separately bundled
  `grant.sh` runs only during explicit, authenticated setup; its username is constrained
  before sudoers interpolation and its privileged tools use absolute system paths.
- Output that the app parses from `sudo` and `pmset` runs under the fixed `C` locale.
  An unexpected battery response is treated as indeterminate and turns keep-awake off,
  rather than silently assuming a full battery.

Launch at login uses Apple's `SMAppService.mainApp` exclusively. The source installer no
longer creates a parallel `~/Library/LaunchAgents` job and removes that obsolete job when
upgrading an installation that used it.

## Lid-close display saving

Display saving does not widen the sudoers grant. When no external display is online,
Sleepless runs Apple's `/usr/bin/pmset displaysleepnow` directly as the logged-in user. When
an external display is online, that command would blank every display, so Sleepless leaves
it alone by default and targets only the cached built-in display instead. The persisted
**Sleep external displays too** switch is off by default and explicitly opts into the
all-display command.

Apple does not provide a documented Apple-Silicon API for changing built-in hardware
brightness. Sleepless therefore resolves only `DisplayServicesGetBrightness` and
`DisplayServicesSetBrightness` at runtime from Apple's fixed
`/System/Library/PrivateFrameworks/DisplayServices.framework` path. It does not search a
user-controlled path or link another binary. If either symbol is unavailable, the operation
fails closed and no external display is changed.

Before setting brightness to zero, Sleepless records the previous value in its preferences.
It removes that recovery value only after restoration on lid-open, turning Sleepless off,
graceful Quit, or a later launch. A hard crash can delay restoration until that later launch;
the normal brightness-up key remains the manual recovery path. Brightness zero saves the
backlight but is not the same reduced-power state as real display sleep. Sleepless sets it
proactively before requesting display sleep and does not capture or monitor keyboard or
pointer events.

## Honest residual risk

The grant is passwordless **by design**: any process already running as your user can flip
the sleep flag silently. We are not pretending the attack surface is zero. But the worst
case is *"your Mac was kept awake, or allowed to sleep."* It is **not** data exfiltration
and **not** root code execution — the two pinned arguments to one Apple binary do not
provide either.

If that trade is not acceptable to you, build from source and **don't** run `install.sh`;
you can toggle `sudo pmset -a disablesleep 1/0` manually instead and skip the grant.

## Reboot resets it (a safety net you can verify)

`disablesleep` is a **runtime** setting. A reboot restores normal sleep — there is no way
for Sleepless to leave your Mac permanently unable to sleep. Verify it yourself: toggle on,
reboot, then `pmset -g | grep SleepDisabled` should read `0`.

Sleepless adds a second belt-and-suspenders: while the app is running, a
**battery-floor auto-off** (default 15%) flips the flag back to `0` while the Mac is awake
and discharging. Graceful termination also attempts to restore normal sleep. A hard crash
or force-quit cannot run cleanup; in that case, reboot or run
`sudo pmset -a disablesleep 0`.

## Code signing, notarization, and Gatekeeper

Sleepless is **ad-hoc signed and not notarized** — it has no paid Apple Developer ID. The
trust model is *read the source, build it yourself*. (Notarization is also not a malware
guarantee: signed, notarized macOS stealers have shipped.)

- **Build from source (recommended):** locally compiled apps are **not quarantined**, so
  Gatekeeper does not prompt — it just runs.
- **Download the prebuilt `.app`:** a release zip carries `com.apple.quarantine`, so
  Gatekeeper blocks first launch. Approve it via **System Settings → Privacy & Security →
  Open Anyway**, then confirm. Note: macOS 15 (Sequoia) **removed** the old
  right-click → Open bypass, so the System Settings path is the supported flow on macOS 15+.

## Why Sleepless can't be on the Mac App Store

Some people trust App Store apps more, so it is worth saying plainly: Sleepless can never
ship there, and that is a property of what it does, not an oversight.

App Review **§2.4.5(v)** states apps "may not request escalation to root privileges or use
setuid attributes." The passwordless root `pmset` toggle is exactly that, so it is the
decisive block. Two more rules independently rule it out: **§2.4.5(i)** (apps must be
sandboxed, and the sandbox has no entitlement for root or arbitrary system-file writes) and
**§2.5.2 / §2.4.5(ii)** (apps must be self-contained in their bundle and may not write
outside their container, which the `/etc/sudoers.d` drop-in does). A privileged-helper
workaround does not rescue it either: a helper installed from a sandboxed app must itself be
sandboxed, so it still cannot write `/etc/sudoers.d` or run arbitrary root commands.

The practical consequence: Sleepless is **direct-download / Homebrew only**, by design. The
verification steps below, plus building from source, are how trust is established instead.

## Verifying a download

If you grab a prebuilt release instead of building it, you can confirm it is genuinely this
project's build, with no Apple account and no shared secret:

```sh
shasum -a 256 -c SHA256SUMS                                  # bytes match what was published
gh attestation verify Sleepless-<version>.zip -R Aboudjem/Sleepless   # built by this repo's release workflow
```

The full walkthrough (what each check proves, how to reproduce the build, and a VirusTotal
scan) is in **[docs/AUDIT.md](docs/AUDIT.md)**.

The release workflow checks out the requested version tag, requires a GitHub-verified signature
on its commit, verifies that both plist version fields match it, pins third-party Actions by
commit SHA, and refuses to overwrite an existing release. Those checks keep a manual workflow
run from silently replacing a tagged artifact.

## Completely removing the privilege

`./uninstall.sh` restores normal sleep, removes the app and login item, deletes the
sudoers drop-in, and then **proves** revocation by showing that `sudo -n pmset …` prompts
for a password again. The single file to audit or delete by hand is
`/etc/sudoers.d/sleepless-disablesleep`.

## Primary sources

- Apple `pmset(1)` man page (no `disablesleep`): https://keith.github.io/xcode-man-pages/pmset.1.html
- Apple open-source `pmset` (`displaysleepnow` implementation): https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmset/pmset.m
- Apple open-source clamshell notification and display handling: https://github.com/apple-oss-distributions/PowerManagement/blob/d415e45501842834a280930c3eed9186544a67f0/pmconfigd/PMDisplay.m
- `brightness` compatibility notes and isolated Apple-Silicon fallback: https://github.com/nriley/brightness
- sudoers manual (exact-arg match, includedir filename rules): https://www.sudo.ws/docs/man/1.9.0/sudoers.man/
- Passwordless sudo for programs (scope / root-own / revoke): https://jozefcipa.com/blog/how-to-use-sudo-without-a-password-in-your-programs/
- Apple — Safely open apps / Open Anyway flow: https://support.apple.com/en-us/102445
- Apple Developer — Sequoia removes Control-click Gatekeeper bypass: https://developer.apple.com/news/?id=saqachfa
- Living without notarization (ad-hoc + quarantine behavior): https://eclecticlight.co/2024/10/01/living-without-notarization/
- App Store Review Guidelines (§2.4.5 root escalation / sandbox / self-contained): https://developer.apple.com/app-store/review/guidelines/
- GitHub artifact attestations (build provenance, SLSA): https://docs.github.com/en/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds
