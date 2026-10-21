# Automatic-update architecture evaluation — issue #17

## Decision

**GO for Sparkle 2 as the architecture for user-approved signed updates; NO-GO for unattended installation or an unconditional production-readiness claim.** The disposable prototype works with an ad-hoc-signed host on macOS 15.7.3 / Apple Silicon. Broader release approval remains blocked on the installation/OS matrix below and publisher-key/release governance. No automatic checks or installation are enabled by this evaluation.

Issue #15 is closed. Its merged implementation already went beyond manual release awareness: `UpdateStore` downloads and installs through Sparkle after separate user actions. This evaluation reuses that working implementation instead of introducing a second updater, removing it, or treating its existence as release sign-off. The existing [update runbook](updates.md) describes its operation. The separate [implementation issue draft](secure-update-rollout-issue.md) captures remaining rollout work; it has not been published to GitHub.

## Actual integration and packaging

The root `Package.swift` pins Sparkle **2.10.0** exactly and links only the app target to its binary product. Sparkle's package manifest pins the downloaded XCFramework by SHA-256; no Xcode project, package installer, new speech engine, or Apple credentials are needed. Swift 6 builds and the real app store compile against this product.

The end-to-end path is:

1. `scripts/make-app.sh` builds the app and CLI, embeds the CLI in `Contents/Helpers`, and uses `ditto` to copy the **entire** Sparkle framework into `Contents/Frameworks`, preserving its versioned symlinks and nested bundles. The executable has an `@executable_path/../Frameworks` runtime search path. Sparkle's license is included in Resources.
2. In the assembled 2.10.0 framework, `Versions/B` contains `Autoupdate`, `Updater.app`, `XPCServices/Downloader.xpc`, and `XPCServices/Installer.xpc`. These are not standalone files to flatten into the host's Helpers directory. Existing nested signatures/entitlements are preserved; the script signs the CLI and outer host ad-hoc, without recursive `codesign --deep` signing.
3. The stable app embeds `SUPublicEDKey` and the official HTTPS feed URL when configured. Dev omits both. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` are true; signed-feed failure expiration is zero. Automatic checks/download/install and profiling are disabled.
4. `scripts/verify-app.sh` checks identity, version/source metadata, CLI execution, runtime linkage and search path, security plist settings, framework and whole-bundle signature integrity. `make-dmg.sh` verifies the resulting image, mounts it read-only, re-verifies the app and compares it with the original bundle.
5. The stable release workflow stamps versions from tags, builds/verifies the bundle and final DMG, then `make-update.sh` creates the signed appcast and signs the DMG. `verify-update.swift` independently verifies Ed25519 archive bytes, length and expected feed metadata. Checksums and provenance cover that same final DMG. Publication remains a human-reviewed draft release.
6. An explicit check invokes `SPUUpdater`. Conure accepts only a signed feed, newer stable version, no non-stable channel, application installation, and the exact official versioned DMG URL. Download and Quit & Install are distinct decisions; pending transcription/model work blocks the latter. Sparkle's helpers validate, extract, replace and relaunch; Conure never shells out to replace itself.

The ad-hoc host has no Developer ID team or Hardened Runtime library validation. Signature integrity checks are not publisher authentication. Sparkle's retained helper signatures do not notarize Conure. Changing the helper inventory, Sparkle version, signing identity or runtime policy requires re-running this evaluation; the [optional Developer ID plan](signing-and-notarization.md) is a separate migration.

## Reproducible local evidence

Run record: **2026-10-21**, base commit `bd71680`, Apple M3 Pro / 18 GB, macOS **15.7.3 (24G419)**, Swift **6.2.3**. Only this OS/hardware combination was exercised locally; macOS 15+ is not thereby fully certified. No production key, GitHub release, installed application, recording or model download was used.

| Check | Observed result |
| --- | --- |
| `swift test` | 105 tests passed, including 15 update-policy/lifecycle tests. |
| `scripts/test-updates.sh --install` | Real Sparkle framework/helpers replaced a disposable ad-hoc host from 1.0.0 to 1.2.3 and relaunched it. |
| Early quit, quit during extraction, cancel at ready | All retained the original app; no later installation/relaunch. |
| Tampered feed; feed signed by another ephemeral key | Sparkle rejected the feed before offering an update. |
| Same-length archive byte mutation; archive signed by another key inside a correctly signed feed | Offered update was rejected before ready/install. Testing both separately avoids attributing archive rejection to a bad feed or mere length mismatch. |
| Correctly signed feed pointing to a Dev-named archive URL | Shipping URL policy refused it before offering/downloading. |
| Dev payload at the allowed stable URL, valid archive/feed signatures | Sparkle rejected the separately named/identified `Conure Dev.app` as having no suitable install for the stable fixture. |
| Dev configuration presented with a stable feed | Updater factory was never called; Dev made no update request. |
| Rejected/cancelled applications | Bundle contents matched a pre-launch snapshot (`diff -qr`), version remained 1.0.0, deep/strict signature verification passed, no relaunch marker. |
| Stable and Dev `make-app.sh` builds | Both packaged successfully; runtime linkage, nested signatures and variant plist checks passed. `codesign -dv` reported the stable host as ad-hoc, with no team. |
| `scripts/make-dmg.sh 1.2.3` | Image checksum, read-only mount, enclosed bundle verification and bundle comparison passed. This is **not** an update launched from a read-only DMG. |

Packaging commands (throwaway public key only; do not distribute these fixtures):

```bash
CONURE_UPDATE_PUBLIC_KEY="$(swift -e 'import CryptoKit; import Foundation; print(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())')" \
  CONURE_REQUIRE_UPDATE_KEY=true scripts/make-app.sh 1.2.3
scripts/make-dmg.sh 1.2.3
scripts/make-app.sh 1.2.3-dev dev
```

These stamp only fixture bundle versions. The source CLI version was deliberately not edited and remained `0.1.0-dev`; these local bundles are not release-version-parity evidence. The real disposable installer test builds its own tiny executable, not the model-loading GUI. It compiles the shipping policy, store and termination delegate directly, changing only transport via a test delegate. Test bundle IDs are `com.conure.updatertest` / `.dev`, not the installed production identities. Private fixture keys live in a restricted temporary directory, are deleted on exit and never enter Keychain or CI secrets. The existing CI integration command now exercises these rejection cases too; this local run does not claim a new hosted CI result.

### Channel boundary and its limits

Production identities remain `com.conure.app` / `Conure.app` and `com.conure.app.dev` / `Conure Dev.app`, with separate model directories. Dev has neither a stable key nor feed, and its shipping configuration refuses to instantiate an updater even if those values were accidentally supplied. Stable excludes Dev URLs, prereleases, named channels and package installers. A normally named/identified Dev payload cannot replace the stable fixture even when signed with the fixture's publisher key.

This proves the tested channel paths, **not** protection from a compromised publisher. Sparkle 2.10.0's `Autoupdate/SUInstaller.m` can select an incoming app by filename before falling back to bundle-identifier matching. Do not assume different bundle IDs alone make a deliberately renamed, publisher-signed Dev payload impossible to install. The trusted packaging path must verify identity and version before signing/publishing, and the follow-up must test mismatched identity/version with the same filename. The archive verifier checks signatures/metadata, not the enclosed app's identity. Never share the stable private key with a future Dev release pipeline; any future Dev updater needs a separate key, feed, publication authority and its own reciprocal negative tests.

## Installation and supported-OS matrix

Repeat tests on macOS 15 and each newer supported major release in disposable logged-in accounts/VMs. Record OS/build, ownership/permissions, signature/key fingerprint, starting and resulting versions, errors and relaunch behavior. Do not test against the maintainer's working app or enable global Gatekeeper bypasses.

| Scenario | Expected behavior / required evidence | Status |
| --- | --- | --- |
| User-writable installation | Validate, replace only selected host, relaunch once, preserve models/transcripts. | Disposable temporary-directory host passed on 15.7.3. `~/Applications` and full GUI remain untested. |
| `/Applications`, user owns app and can write parent | Same without unnecessary elevation; verify exact replaced path. | Not run. |
| `/Applications`, admin-owned / non-admin session | Sparkle authorization flow; cancelling preserves original. Verify ownership and no persistent privileged service. | Not run. |
| Read-only mounted DMG | Refuse updating with move-to-Applications guidance; do not silently choose another installed copy. | Source-reviewed (`SPUBasicUpdateDriver.m`); live launch not run. Read-only packaging verification is a different check. |
| Quarantined download / app translocation | Test actual Finder launch/path and refusal/guidance, then move to Applications and retry. | Not run; non-quarantined direct fixture execution does not reproduce translocation. |
| Full disk, disconnected download, cancelled authorization | Clear failure/cancellation; old application remains runnable; retry is safe. | Unit-level error states covered; filesystem/authorization fault injection not run. |
| Other supported macOS versions | Repeat real helper install, negative signatures/channels, cancellation, Gatekeeper and permissions. | Not available in this local run. |

The framework's updater/installer IPC and permission design is described in Sparkle's pinned `Documentation/Installation.md`. That design review does not replace the untested rows. Initial Gatekeeper warnings remain: Ed25519 updates do **not** confer Developer ID identity, Apple notarization or Apple approval. Follow the README's per-app first-launch instructions.

## Key custody, CI and recovery

- **Authority:** maintainers designate a project-controlled stable signing identity and named custodians/backup holders. `generate_keys --account com.conure.updates` stores the private identity in the macOS Keychain; only the public base64 key belongs in `CONURE_UPDATE_PUBLIC_KEY` and the app. Record a public-key fingerprint in the release record and verify it against the intended installed cohort.
- **CI access:** current `release.yml` reads the repository secret `SPARKLE_PRIVATE_KEY` only for stable tag appcast signing, passing it via stdin; normal CI/Dev uses ephemeral/no keys. The build job runs checkout code and dependencies, so a malicious trusted-tag workflow can exfiltrate the key despite log masking. Before rollout, restrict tag creation and workflow edits, use a protected release environment with required reviewers and narrowly scoped signing access, and pin/review Actions and binary dependencies. Do not expose production secrets to PRs, forks or `pull_request_target`; do not cache/export key files or use shell tracing. A public key and GitHub token are not substitutes for the signing secret.
- **Backup:** export a restricted key file using the runbook, encrypt it for offline recovery in a project-controlled vault, and keep a second encrypted copy under independent custody. Keep decryption/recovery credentials separately. Document owner, public fingerprint and recovery steps without secret values. Test restoration with a disposable key and known fixture before relying on the procedure; re-test after custody changes. GitHub Actions secrets cannot be read back as a backup.
- **Planned rotation:** do not simply replace the public variable and secret. An old ad-hoc host trusts the old key, and signed feeds with expiration zero cannot fall back to an unsigned/new-key feed. A bridge release signed by the old key with a new embedded key needs a verified feed/cohort migration design; offline users skipping that bridge must still be accounted for. No such design is proven here. Until then, intentional rotation requires a documented manual reinstall of a separately verified release, with both keys backed up during transition. Never disable pre-extraction or feed verification to ease rotation.
- **Loss:** freeze signed releases, restore the same identity from a verified backup and check its public fingerprint before resuming. If no backup exists, declare the old channel unable to update; issue public instructions for manual installation using independent provenance checks and a new key. Ad-hoc signatures cannot recover the old trust chain.
- **Compromise:** stop publication/signing access, revoke compromised CI access, audit workflows/assets and notify users through independent channels. Treat old-key-signed updates as potentially hostile. The old key cannot securely announce its own revocation to already-compromised clients, so recovery may require manual installation from an independently verified source. Replacing a GitHub secret alone does not revoke trust in installed apps. Record an incident review before resuming.

The offline restore, protected CI environment and key migration are **requirements**, not actions performed by this evaluation. No production key was requested or provisioned.

## Rollback and interrupted updates

- Conure refuses version downgrades at policy level; Sparkle also checks version ordering. Repointing `latest` to an older release is not a rollback channel. Prefer a newly versioned, reviewed fix-forward release. For emergency manual rollback, quit the app, verify an older artifact's provenance, reinstall manually and check data compatibility; never loosen signature/version checks in the updater.
- Sparkle stages the new app and attempts atomic swap where safe, otherwise a legacy move-and-restore path (`Autoupdate/SUPlainInstaller.m`). It attempts restoration on a failed move. This is not a guaranteed transactional rollback of the app, models, transcript formats or user state after every crash/power failure.
- The disposable tests prove orderly cancellation before check completion, during extraction and at ready preserves the original. They do **not** prove safety of killing helpers, losing power during final replacement, volume removal or failed relaunch. Force-kill/power-loss tests belong in disposable VMs; verify which bundle survives and that retry/manual recovery works. Do not kill a live privileged installer on a user's machine to test this.
- A failed/cancelled download or verification must never request Quit & Install; successful installation followed by an app crash has no automatic health-based rollback. Recover through a verified fix-forward/manual reinstall. Models/transcripts live outside the bundle but future schema changes need their own migration/backup strategy. The queue currently is not persisted, so deliberate installation must remain blocked during queued/running/model work (related queue persistence: #22).

## Security and maintenance trade-offs

| Option | Benefit | Cost / decision |
| --- | --- | --- |
| Manual GitHub Releases installation | Smallest installer attack surface; independent provenance possible. | User effort; retain as recovery/fallback, especially for older apps and key loss. |
| Sparkle 2 + signed feeds and Ed25519 archives | Working SwiftPM/ad-hoc prototype; established installer/helper lifecycle and pre-extraction authentication; no paid Apple membership. | Additional binary/helper supply chain, key custody and privileged replacement surface. Chosen for explicit user-approved updates after rollout gates. |
| Custom self-replacement shell/helper | Superficially small dependency footprint. | Would recreate race/TOCTOU, permission, rollback and relaunch machinery. Rejected. |
| Developer ID + notarization | Improves initial distribution identity and Gatekeeper experience. | Paid credentials and separate migration/validation. Complementary to, not a substitute for, update signing. |

A signed feed prevents unauthorized metadata/release-note changes; an archive signature authenticates exact download bytes against the installed trust anchor. Neither protects a compromised signer/build pipeline, guarantees safe application logic, or prevents feed withholding/denial of service. HTTPS and exact repository URLs are additional origin constraints, not cryptographic publisher identity. Attestations support independent artifact provenance; checksums alone do not authenticate the publisher, and reproducible builds have not been established.

Maintain the exact Sparkle pin/checksum, monitor security releases, re-inventory nested helpers after upgrades, and rerun signing/negative/install tests for changes. Keep delta generation disabled until separately validated. The cost of this ongoing work is why a working local prototype is not approval for unattended updates.

## Completion boundary

The architecture choice, SwiftPM/framework packaging, local ad-hoc installation, Ed25519 verification, tamper/wrong-key rejection, tested channel isolation and recovery design are recorded here. The supported-OS/permission/translocation/power-loss matrix is explicitly incomplete; do not check those acceptance criteria as fully validated or treat this document as unrestricted release sign-off. The follow-up draft defines observable requirements to resolve those gaps without enabling unattended installation by default.
