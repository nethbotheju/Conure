# Harden and validate signed-update rollout before production approval

Draft only — not published. Suggested existing labels: `enhancement`, `area: app`, `area: release`, `testing`, `priority: high`. Suggested milestone: **v0.3 — Distribution, Updates, and Trust** (maintainer to confirm).

## Problem

The #17 evaluation demonstrates Sparkle 2.10.0 with Conure's pure SwiftPM packaging and an ad-hoc-signed host on macOS 15.7.3. Signed replacement/relaunch and tamper, wrong-key and channel-rejection tests pass locally. However, other supported OS versions, privileged installation, quarantined/translocated launch and interrupted final replacement have not been validated. Publisher custody and protected release-key access are also not established by code or the local test.

The updater already exists from #15. Its presence must not be mistaken for release approval, and safe packaging must not rely on bundle identifiers alone: Sparkle can select incoming bundles by filename. A correctly signed but wrongly packaged payload is a publisher mistake that signatures alone cannot prevent.

## Proposed solution

Harden the existing publication boundary and complete the missing release validation before approving production rollout. Reuse the current policy/store and disposable harness; do not build a second updater or enable background/unattended installation as part of this work. Preserve manual release-page installation as a recovery path and keep Conure Dev manual-only.

## Acceptance criteria

- [ ] Before signing/publication, verify the actual enclosed app's stable bundle identifier, filename, app version, CLI version and expected update public key against the requested release. Missing or mismatched values abort publication without uploading a feed. Add disposable fixtures for Dev content renamed to `Conure.app` and wrong-version content, including otherwise valid signatures.
- [ ] Repeat the real helper installation/relaunch and rejection suite on macOS 15 and each newer supported major version; record exact OS/build, hardware, starting/resulting versions and limitations. No real installed app, model download or publisher secret is required for these tests.
- [ ] Validate disposable installations in `~/Applications`, user-writable `/Applications`, and admin-owned `/Applications` from a non-admin session. Successful updates replace only the selected host and relaunch once; cancelled/failed authorization preserves the old app and ownership.
- [ ] Validate a real quarantined Finder download, app translocation and read-only DMG launch. Updating from unsuitable locations must give actionable move/relaunch guidance without silently replacing another installed copy. Record actual launch paths; mounting a DMG for packaging checks is not sufficient evidence.
- [ ] In disposable VMs, inject download interruption, low disk space, final replacement interruption and failed relaunch. Record the surviving bundle, signature integrity and safe retry/manual recovery procedure; do not claim transactional rollback where it is not demonstrated.
- [ ] Preserve two-step download/install consent, no scheduled checks/downloads/installation or profiling, and refusal to quit with pending transcription/model work. Cancellation/ordinary quit must not schedule later installation; retain automated lifecycle tests.
- [ ] Preserve and rerun stable-to-Dev and Dev-to-stable rejection tests, including separate bundle contents/identity and exact official archive URL checks. Any future Dev updater requires a separate design/key/feed and is out of scope.
- [ ] Establish named key custodians, an encrypted offline backup and a tested restore drill using a disposable identity. Document loss/compromise/manual-reinstall procedures. Do not rotate the production key without a separately validated bridge/offline-cohort plan or an explicit manual reinstall migration.
- [ ] Restrict stable signing to a protected release environment with required reviewers, trusted tags/workflows and narrowly scoped secret access. Normal CI, PRs and Dev builds never receive production signing secrets; signing/publication failures abort rather than falling back to unsigned artifacts.
- [ ] Record a maintainer go/no-go sign-off against the complete matrix and update the README/runbook to match only verified release behavior. Developer ID/notarization status remains explicit; update signatures never imply Apple approval.

## Additional context

Follow-up to #17; #15 already supplied the updater and #16 documents an optional, still-disabled Developer ID migration. Coordinate busy-work/queue expectations with #22 without making speech-model tests or queue persistence a prerequisite for disposable installer tests.

Evidence and constraints: `validation/automatic-update-evaluation.md`, `validation/updates.md`, `scripts/make-app.sh`, `scripts/make-dmg.sh`, `scripts/make-update.sh`, `scripts/verify-app.sh`, `scripts/verify-update.swift`, `scripts/test-updates.sh`, `Tests/UpdateHarness/UpdateHarness.swift`, `App/Sources/ConureApp/UpdatePolicy.swift`, and `.github/workflows/release.yml`.

The local prototype is not evidence for production-key provisioning, hosted GitHub publication, other supported macOS releases or privileged installs. Version stamping remains tag-driven; do not hand-edit `ConureVersion.swift`. Perform secret setup privately through approved publisher tooling, never via issue comments, logs or committed fixtures.
