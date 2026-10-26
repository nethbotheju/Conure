# Evaluation: secure automatic updates for ad-hoc-signed builds

Status: **complete — decision: GO**, with conditions listed under [Decision](#decision).
Recorded 2026-10-26. Issue #17. Operator guide: [`validation/updates.md`](updates.md). User-facing behaviour: [README → Check for updates](../README.md#check-for-updates).

## Question

Conure ships as a pure SwiftPM project, assembled into an app bundle by `scripts/make-app.sh`, ad-hoc signed (no Developer ID, no notarization), and distributed from GitHub Releases. Can that distribution model support automatic in-app installation of updates without weakening the security of an app whose only integrity guarantee today is a checksum plus a build attestation?

Shipping automatic installation was not a requirement of the evaluation. The requirement was a decision backed by a working prototype rather than an assumption.

## Method

An end-to-end prototype was built and executed rather than reasoned about on paper. The prototype is the code now in `main`: `App/Sources/ConureApp/UpdateStore.swift` (custom `SPUUserDriver`), `UpdatePolicy.swift` (acceptance rules), `UpdatesView.swift` (SwiftUI states), `scripts/make-update.sh` (feed generation/signing), `scripts/verify-update.swift` (independent verification), `scripts/test-updates.sh` (disposable install harness), and the packaging/workflow changes.

Environment for the recorded run:

| Item | Value |
|---|---|
| Host | macOS 15.7.3 (24G419), Apple Silicon arm64 |
| Toolchain | Swift 6, Xcode default |
| Sparkle | 2.10.0, pinned `exact`, revision `eef1a53` |
| CI | `macos-15` arm64, `.github/workflows/ci.yml` |

Commands executed and their results:

| Command | Result |
|---|---|
| `swift build` | Build complete |
| `swift test` | 105 tests, 0 failures (15 in `UpdateTests`) |
| `scripts/test-updates.sh` | `Update signing tests passed: valid feed/archive, wrong key, tampered archive, tampered feed.` |
| `scripts/test-updates.sh --install` | `Disposable application cancellation, replacement, and relaunch tests passed.` |
| `CONURE_UPDATE_PUBLIC_KEY=<throwaway> scripts/make-app.sh 0.1.0 stable` | Bundle assembled and verified; `codesign --verify --deep --strict` valid; `spctl -a` rejected (expected) |

The install harness is not a mock: it compiles the real `UpdatePolicy`/`UpdateStore` into a small harness app with a separate bundle identifier, serves a signed appcast and signed DMG over loopback, and runs three cancellation modes plus a real install. The final case replaces a temporary `Conure.app` (1.0.0 → 1.2.3) through Sparkle's own installer helpers, relaunches it once, and re-verifies the bundle signature; every cancellation mode leaves the original bundle byte-identical. A production app, a real GitHub release, and the publisher key are never touched.

## Candidates considered

| Candidate | Verdict |
|---|---|
| **Sparkle 2 + Ed25519-signed appcast and archives** | **Chosen.** Trust comes from a publisher key that is independent of Apple code signing, so it works with an ad-hoc bundle. Verification happens before extraction, uses Sparkle's signed helper processes for replacement and relaunch, and requires no self-replacing shell script. |
| Manual GitHub Releases check only (issue #15) | Kept as the fallback and as the behaviour of every build that lacks the publisher key. Does not install, so users still perform a full manual reinstall. Retained deliberately: a build without a key degrades to this, it does not fail. |
| Custom in-app downloader that replaces its own bundle | Rejected. A running process replacing its own code, escalating privileges, relaunching, and rolling back is exactly the class of code that must not be hand-written here. It also cannot be tested cheaply and would need its own signing story. |
| Homebrew cask / package manager | Rejected. Requires users to adopt a package manager, and cask updates re-download rather than update in place. Not appropriate for a general-audience GUI app. |
| Developer ID + notarization first, updater later | Rejected as a prerequisite. Notarization does not remove the need for update authenticity, and requiring a paid membership would block the project indefinitely. Issue #16 keeps the optional paid path available; this decision does not depend on it. |
| Other update frameworks (`AppUpdater`, `electron-sparkle-updater`, vendor updaters) | Rejected. Either they assume a Developer ID trust chain, or they wrap Sparkle with less control over acceptance policy than the direct integration provides. |

## Findings that shaped the design

1. **The pinned Sparkle framework is itself ad-hoc signed.** `codesign -dv` on the SPM artifact reports `Signature=adhoc`, `TeamIdentifier=not set`, identifier `org.sparkle-project.Sparkle`. Nothing in the update chain relies on an Apple-issued identity, so an ad-hoc host and ad-hoc nested code are consistent with each other. This works only because Conure has no Hardened Runtime and no library validation; enabling either would break loading ad-hoc Sparkle without an Apple Development certificate.
2. **Trust therefore rests entirely on the Ed25519 key.** `SUPublicEDKey` in `Info.plist` authenticates both the feed and the archive. `SURequireSignedFeed` plus `SUSignedFeedFailureExpirationInterval = 0` remove Sparkle's unsigned-feed fallback window, and `SUVerifyUpdateBeforeExtraction` moves archive verification ahead of extraction, so a forged archive is never written to disk.
3. **Repository compromise alone is not sufficient to push an update.** An attacker who can publish a release still cannot produce a valid signature; `scripts/verify-update.swift` and the app both reject it. The exception is CI-secret access, covered in the threat model below.
4. **Packaging cost is small but real.** SwiftPM builds the app target; the framework is copied by `make-app.sh` and located through `linkerSettings: -rpath @executable_path/../Frameworks`. `verify-app.sh` asserts the framework directory, the Sparkle licence, the `@rpath/Sparkle.framework/` load command, the rpath, `codesign --verify --deep --strict` on the framework, and the updater plist keys. Sparkle contributes 2.9 MB of a 59 MB bundle, plus `Autoupdate`, `Updater.app`, and (unused, since Conure is not sandboxed) `Downloader.xpc`/`Installer.xpc`.
5. **SwiftPM integration is a one-time, pinned dependency.** `exact: "2.10.0"` keeps update behaviour from changing silently; the app target must stay a bundle-embedded executable, so `swift run ConureApp` produces an unpackaged process where in-app updates are deliberately disabled.
6. **The acceptance policy, not Sparkle's defaults, is the security boundary.** `UpdatePolicy.accepts` requires a signed feed, no `sparkle:channel`, `installationType == application`, a newer *stable* semantic version, and an archive URL equal to `https://github.com/nethbotheju/Conure/releases/download/v<version>/Conure-<version>.dmg`. Downgrades, prereleases, other repositories, `Conure-Dev-*` artifacts, query-string variants, and package installers are refused.

## Threat model

| Threat | Mitigation | Verified by |
|---|---|---|
| Malicious feed (DNS/CDN/GitHub compromise) | Feed signature required; no expiration fallback | `sign_update --verify`, `verify-update.swift`, `test-updates.sh` tampered-feed case |
| Malicious or substituted archive | Ed25519 signature over the archive plus exact size and URL check, before extraction | `test-updates.sh` tampered-archive and wrong-key cases |
| Archive from another project or fork | Exact official URL match, version match | `UpdateTests.testOnlySignedNewerStableOfficialApplicationUpdatesAreAccepted` |
| Downgrade / replay of an old signed release | `candidate > installed` required | same test |
| Prerelease or draft leaking into stable | Prereleases get no appcast; drafts are not public; `sparkle:channel` refused | `release.yml`, `verify-update.swift` |
| Dev/stable channel crossover | Dev bundle has no `SUFeedURL`/`SUPublicEDKey` and a hard `disabledReason`; stable policy rejects `Conure-Dev-*` | `verify-app.sh`, `UpdateTests.testDevelopmentAndUnknownVersionsNeverStartUpdater` |
| Silent or unwanted installation | `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUAllowsAutomaticUpdates`, `SUEnableSystemProfiling` all false; download and install are separate explicit actions; cancelling at the ready stage sends `.skip`, so nothing installs on a later quit | `verify-app.sh`, `UpdateTests`, install harness cancel modes |
| Data loss during install | Install refused while jobs or model operations are active | `UpdateTests.testBusyWorkBlocksInstallWithoutDiscardingDownloadedUpdate` |
| Update consent prompt / profiling exfiltration | `show(_:reply:)` always answers "no automatic checks, no profile"; `allowedSystemProfileKeys` is empty | `UpdateStore` |

Explicitly out of scope: a compromised publisher machine or CI secret, a local administrator, a Sparkle vulnerability, and the Gatekeeper first-launch warning. **Sparkle signatures do not replace notarization.** A first install of an ad-hoc-signed app is still blocked by Gatekeeper until the user approves it (issue #12 documents that flow), and this evaluation does not change that.

## Publisher key lifecycle

Details and commands live in [`validation/updates.md`](updates.md#one-time-publisher-setup); the decision-level summary:

- **Storage.** One Ed25519 identity in the publisher's login Keychain (`--account com.conure.updates`). The private key never enters the repository, a build log, or a command-line argument; `make-update.sh` reads it from stdin.
- **CI access.** Repository Actions secret `SPARKLE_PRIVATE_KEY` (private key) and Actions variable `CONURE_UPDATE_PUBLIC_KEY` (public key, also embedded by `make-app.sh`). Stable tag builds fail closed: `CONURE_REQUIRE_UPDATE_KEY` makes the build abort if the public key is missing, and `make-update.sh` aborts if either value is absent.
- **Backup.** The Keychain identity must be exported and stored offline, outside this checkout. This is the single point of irreversible trust loss.
- **Rotation.** Sparkle 2 supports one public key per app, and the key is baked into the installed bundle. Rotation is therefore a two-release operation: ship a transition release signed with the *old* key whose `Info.plist` carries the *new* `SUPublicEDKey`, then sign subsequent releases with the new key. Never rotate silently and never disable verification to make a rotation work.
- **Loss recovery.** A lost private key cannot be recovered cryptographically. Recovery is a documented manual path: publish a new release, tell users to install it manually once (DMG from Releases), and accept that older versions can no longer update themselves. There is no in-app recovery and none is planned.
- **Compromise.** A leaked key is an incident, not a configuration change: rotate per the two-release procedure, publish an advisory, treat every release signed in the exposure window as suspect, and verify user archives against the published checksums and attestations.

**The dominant residual risk is CI secret access.** Anyone who can push a tag to `main` can modify `release.yml` to exfiltrate `SPARKLE_PRIVATE_KEY`, which makes repository write access effectively equivalent to key compromise. Mitigations are process controls, not code: protected tags for `v*`, required review on `.github/workflows/**`, and a protected release environment requiring manual approval. These are repository settings and must be configured by the publisher.

## Installation scenarios

Conure makes no attempt to detect its own installation location; Sparkle owns this and reports through `showUpdaterError`, which the app displays with Sparkle's recovery suggestion. Behaviour and the resulting guidance:

| Scenario | Behaviour | User guidance |
|---|---|---|
| `/Applications` (admin-owned) | Sparkle asks for administrator authorization through its signed `Autoupdate`/`Updater.app` helpers | Authenticate, or cancel and keep the current version |
| `~/Applications` (user-writable) | Updates in place with no authorization prompt | None |
| Running from the read-only DMG | Sparkle refuses to update on any read-only volume | Copy Conure to Applications, then update |
| App-translocated (quarantined, launched from DMG/Downloads) | Sparkle reports `SURunningTranslocated` (1005) | Move the app to Applications and relaunch |
| Install location not writable (`SUInstallationWriteNoPermissionError`, 4012) | Installation fails, original app preserved | Move to a writable location or install manually |
| Insufficient disk space | Extraction/installation fails, original app preserved | Free space and retry; the download is not left half-installed |
| Multi-user Mac | Each user account has its own update cache; `/Applications` requires an admin account | Update from an admin account |
| Conure Dev, prerelease, or unpackaged build | No update check at all; explicit "updates not configured" state | Install dev snapshots from Actions artifacts |

The disposable harness covers writable-location replacement. The read-only, translocated, and no-permission paths are documented from Sparkle's error contract and the manual release checklist, not exercised in CI — recorded as residual work.

## Rollback and interrupted updates

- **No automatic rollback.** Sparkle has none, and Conure adds none. A bad release is recovered by manually installing a previous DMG from the Releases page. This is the reason the release workflow keeps every versioned DMG rather than only the latest.
- **Interrupted before download completes.** Nothing is staged; the current app is untouched. A partial download is discarded or resumed from Sparkle's cache, not installed.
- **Interrupted during download/extraction/preparation.** The bundle is never modified; the harness verifies byte-identical preservation in each cancellation mode.
- **Cancelled at the ready stage.** `.skip` is sent, so Sparkle will not install on a later ordinary quit. This was a deliberate change: `.dismiss` would have scheduled installation on quit, which contradicts "cancel".
- **Quit during an active update cycle.** `UpdateApplicationDelegate` cancels the quit, cancels the session, and reissues quit after the cycle ends; it does not use `terminateLater`, which would block Sparkle's main-queue cancellation callbacks.
- **Interrupted during installation** (crash, power loss, killed helper). Sparkle stages the replacement and swaps the bundle instead of writing into the running one, so the expected outcome is either the old or the new app, never a half-written one. This is design-level reasoning, not yet exercised — it is on the follow-up checklist. If termination fails, the app surfaces "Retry Quit & Install" instead of hanging.
- **Failed verification.** No extraction, no replacement, and an explicit error; the app never reports "up to date" for a validation failure.

## Trade-offs

Gains: authenticity independent of Apple identity (the only option available to an ad-hoc-signed project), verification before extraction, tested cancellation and busy-work protection, no self-replacing shell code, and a fail-closed default for builds without a key.

Costs, accepted:

- One pinned third-party dependency (Sparkle 2.10.0) with its own release cadence and 2.9 MB bundle cost.
- A permanent publisher secret in CI, and a trust root that is a single Ed25519 key with no Apple-backed recovery path.
- Release process gains an appcast generation/signing step and a human publish gate; a stable release published without a signed appcast is a broken release.
- `latest` semantics come from GitHub's latest non-prerelease redirect, so release ordering and prerelease flagging are now correctness-critical, not cosmetic.
- Every future packaging change (bundle layout, helpers, signing order) must keep `verify-app.sh` and the install harness green.
- The updater cannot fix the first-launch Gatekeeper warning, and must not be presented as if it does.

## Decision

**GO.** Sparkle 2 with Ed25519-signed feeds and archives is adopted as Conure's update mechanism for stable releases, under these conditions:

1. The publisher key is provisioned and backed up before the first updater-enabled stable release; stable tag builds continue to fail closed without it.
2. `scripts/test-updates.sh --install`, `scripts/verify-update.swift`, and `verify-app.sh` remain mandatory in CI and in the release path.
3. Protected tags, required workflow review, and an approval-gated release environment are configured before the key is placed in CI.
4. The read-only, translocated, no-permission, and macOS-major-upgrade paths are exercised on a disposable account or VM before the first updater-enabled release.
5. Conure Dev keeps no feed, no key, and no update path. Any future dev update channel is a separate decision.

Acceptance criteria from issue #17 and their evidence:

| Criterion | Status | Evidence |
|---|---|---|
| Sparkle 2 evaluated with pure SwiftPM | Verified | `Package.swift`, `make-app.sh`, framework embedding verified by `verify-app.sh` |
| Framework/helper packaging through `make-app.sh` | Verified | Assembled bundle inspected: `Sparkle.framework`, `Autoupdate`, `Updater.app`, rpath, deep strict signature |
| Ad-hoc signature operation on supported macOS | Partially verified | macOS 15.7.3 locally and `macos-15` in CI, including a real replace/relaunch; macOS 26 not yet exercised |
| Ed25519 verification demonstrated locally | Verified | `test-updates.sh`, `verify-update.swift` |
| Tampered/incorrectly signed archives rejected | Verified | `test-updates.sh` tampered-archive, tampered-feed, wrong-key cases |
| Key storage, CI access, backup, rotation, loss recovery documented | Verified | [Key lifecycle](#publisher-key-lifecycle), `validation/updates.md` |
| Stable and dev channels cannot replace each other | Verified | `verify-app.sh` plist assertions, `UpdatePolicy`, `UpdateTests` |
| DMG/translocation/`/Applications`/user-writable considered | Partially verified | [Installation scenarios](#installation-scenarios); analysed from Sparkle's error contract, only writable-path exercised in CI |
| Rollback and interrupted-update behaviour documented | Verified | [Rollback and interrupted updates](#rollback-and-interrupted-updates) |
| Security and maintenance trade-offs recorded | Verified | This document |
| Go/no-go decision recorded | Verified | Above |
| Implementation issue drafted if GO | Verified | Appendix |

## Follow-up

The prototype shipped ahead of this decision (commit `4de9429`), so the follow-up issue below is hardening and validation rather than new implementation. It is drafted here because filing issues is a maintainer action; publish it with the command in the appendix.

## Appendix: draft follow-up implementation issue

Title: **Harden and validate signed in-app updates before the first updater-enabled stable release**

Body:

> ## Problem
>
> The Sparkle-based updater is in `main` and the go decision is recorded in `validation/updates-evaluation.md`, but several conditions of that decision are unverified or unconfigured. Until they are met, publishing a stable release would expose users to an update path whose failure modes have not been exercised.
>
> ## Requirements (all verified before the first updater-enabled stable release)
>
> - [ ] Protected `v*` tags, required review for `.github/workflows/**`, and an approval-gated release environment exist before `SPARKLE_PRIVATE_KEY` is added to CI.
> - [ ] `CONURE_UPDATE_PUBLIC_KEY` and `SPARKLE_PRIVATE_KEY` are provisioned per `validation/updates.md`; the private key is backed up offline; no key material is in the repository or logs.
> - [ ] A release rehearsal runs with a throwaway test key end to end: tag → build → signed appcast → draft release → updater finds, downloads, installs, and relaunches on a disposable macOS account or VM.
> - [ ] The rehearsal is repeated on the current macOS major release, not only macOS 15.
> - [ ] Read-only DMG, translocated, and non-writable-location launches show actionable errors and leave the existing app installed and runnable.
> - [ ] Insufficient disk space and cancelled administrator authorization leave the existing app installed and runnable.
> - [ ] An interrupted installation (killed helper or forced restart) leaves either the old or the new bundle, never a partially written one.
> - [ ] A key-rotation rehearsal completes with a transition release that carries the new public key and is signed with the old one.
> - [ ] Conure Dev and unpackaged builds confirm no network request to the stable feed (proxy or `nettop` evidence), and never replace stable Conure.
> - [ ] A published stable release missing its appcast is detected before publication, not after.
> - [ ] Rollback procedure (manual reinstall of a previous DMG) is written into the release checklist and referenced from `validation/updates.md`.
>
> ## Out of scope
>
> Automatic checks, scheduled checks, silent installation, delta updates, and any development update channel. Each is a separate decision.

Publish with:

```bash
gh issue create \
  --title "Harden and validate signed in-app updates before the first updater-enabled stable release" \
  --label "enhancement" --label "area: release" --label "priority: high" \
  --body-file <(sed -n '/^## Appendix: draft follow-up/,/^Publish with:/p' validation/updates-evaluation.md \
                | grep '^>' | sed 's/^> \{0,1\}//')
```

## References

- [Sparkle documentation](https://sparkle-project.org/documentation/), [publishing/signing](https://sparkle-project.org/documentation/publishing/), [custom user driver](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html)
- [`validation/updates.md`](updates.md) — publisher setup, release workflow, manual release checks
- [`validation/signing-and-notarization.md`](signing-and-notarization.md) — optional Developer ID path (issue #16)
