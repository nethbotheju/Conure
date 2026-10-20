# Optional Developer ID signing and notarization

## Status and scope

**Design only: the paid path is disabled.** Conure has no project-controlled Developer ID credentials or validated notarized release. Do not enable it merely by adding secrets. A reviewed implementation and successful end-to-end validation with genuine project-controlled credentials must precede enablement.

The default remains ad-hoc signing, without Apple Developer Program membership. Contributors, forks, PR CI, development builds, and local builds need no Apple credentials. Normal CI does not read Apple secrets. Existing Sparkle Ed25519 update-signing credentials are separate: stable releases still require those as described in [signed in-app updates](updates.md). They do not require paid Apple membership and are not replaced by Developer ID signing.

The implemented preparation consists of a fail-closed configuration preflight, not certificate import, entitlement changes, or notarization commands. It neither contacts Apple nor changes existing signing commands.

## Current release flow

1. `.github/workflows/release.yml` accepts `vX.Y.Z` tags (including supported prerelease suffixes), validates the version, and injects it into the CLI for that build. Manual dispatch builds an artifact without publishing a release.
2. `scripts/make-app.sh` builds the SwiftPM executables, embeds `conure` in `Contents/Helpers`, and copies the pinned Sparkle framework. It writes version, source metadata, and updater configuration before signing.
3. The script ad-hoc signs the CLI, then the app. It preserves Sparkle's existing nested signatures. `scripts/verify-app.sh` checks bundle identity, versions, metadata, CLI execution, framework linkage, and signatures.
4. `scripts/make-dmg.sh` packages the app and Applications link, verifies the image, mounts it read-only, rechecks the app, and compares it with the original bundle.
5. For stable tags, `scripts/make-update.sh` signs the final DMG and appcast with Sparkle's update key. CI then checksums and attests the DMG and creates a draft release. Prerelease tags omit the stable feed.

Enabling Apple signing must not change tag-based versioning, bundle identifiers (`com.conure.app` and `com.conure.app.dev`), source metadata, draft publication, or Sparkle's independent signature requirements. Never hand-edit `ConureVersion.swift` to enable signing.

## Credential contract

These are reserved configuration names, not instructions to configure production now. Empty and unset values both count as missing. Local packaging reads environment variables; the release workflow explicitly maps these Actions variables/secrets only into its preflight step. No values belong in Git, fixtures, logs, command tracing, release assets, or chat.

| Name | Storage | Purpose |
| --- | --- | --- |
| `CONURE_SIGNING_MODE` | Actions variable | Unset/empty or `adhoc` selects the default. `developer-id` requests the future paid path, currently rejected. Other values fail. |
| `CONURE_SIGNING_IDENTITY` | Actions variable | Exact Developer ID Application signing identity, preferably its certificate SHA-1 fingerprint to avoid ambiguous names. Not an Apple Development, App Store, or Developer ID Installer certificate. |
| `CONURE_APPLE_TEAM_ID` | Actions variable | Expected Apple Developer team identifier; validate the imported identity and signed artifacts against it. |
| `CONURE_DEVELOPER_ID_P12_BASE64` | Actions secret | Base64-encoded PKCS#12 export containing the Developer ID Application certificate **and private key**. Base64 is not encryption. |
| `CONURE_DEVELOPER_ID_P12_PASSWORD` | Actions secret | Password protecting that PKCS#12 export; use a nonempty password. |
| `CONURE_NOTARY_KEY_ID` | Actions variable | Identifier of the App Store Connect API key authorized for notarization. |
| `CONURE_NOTARY_ISSUER_ID` | Actions variable | Issuer UUID for the project's team App Store Connect API key. This design uses a team key, not an individual key. |
| `CONURE_NOTARY_PRIVATE_KEY` | Actions secret | Contents of the matching private `.p8` API key, used by `xcrun notarytool` with the key ID and issuer ID. |

The certificate signs code; the App Store Connect key authenticates notarization submissions. Both must be usable by the project under its paid Apple Developer Program membership. No App Store app listing or Developer ID Installer certificate is needed for the app/DMG distribution design. An Apple Account/app-specific password or an interactive login is not an additional requirement: this design chooses API-key authentication instead of that alternative.

**Release governance:** use a project-controlled team with documented release approvers, credential custodians, renewal/revocation, backup, and incident procedures. Do not borrow an unrelated contributor's personal certificate or API key without explicit ownership, authorization, continuity, and release-governance agreements. Funding alone does not establish those controls. Keep certificate and update-key recovery plans separate.

A future implementation must decode/import the certificate into a temporary, job-specific keychain, validate identity, private-key availability, certificate expiry, and team, and restore the runner's original keychain search list afterward. Generate an ephemeral keychain password locally; do not store it in the repo. Write certificate/API-key files under the runner's temporary directory with restrictive permissions, disable shell tracing, and delete files and keychain on success, failure, or cancellation (`always()` cleanup in CI as well as shell traps). Never upload or cache the keychain, `.p12`, `.p8`, passwords, or credential-bearing logs.

## Fail-closed configuration policy

`scripts/check-apple-signing.sh` runs before building or modifying packaging output in both `make-app.sh` and `make-dmg.sh`. The release workflow also runs it before version injection. It reports missing **names**, never values. It only checks configuration presence, not credential validity.

The seven rows after `CONURE_SIGNING_MODE` constitute one complete Apple credential set:

| Configuration | Behavior now | Required behavior after a validated implementation |
| --- | --- | --- |
| No Apple credentials; mode unset/empty or `adhoc` | Continue existing ad-hoc packaging. | Same. |
| Some but not all seven credential fields, with either valid mode | Fail explicitly, listing missing fields; no ad-hoc fallback. | Same. |
| Complete credentials; mode unset/empty or `adhoc` | Fail: paid path disabled; do not ignore credentials. | Fail mode/credential mismatch; require explicit opt-in. |
| No credentials; mode `developer-id` | Fail: paid path disabled. | Fail with missing credential names. |
| Complete credentials; mode `developer-id` | Fail: paid path disabled. | Validate credentials and sign/notarize; any failure aborts publication. |
| Unknown mode | Fail configuration validation. | Same. |

Only absence of Apple configuration permits ad-hoc packaging; import, signing, timestamp, network, notarization, or stapling failures must never trigger fallback. Remove all seven Apple fields and reset/unset the mode to return to the intentional ad-hoc path. Do not put credentials into repository settings until ready for a separate enablement change: even a complete set currently blocks release packaging by design.

PR/push CI runs `scripts/test-apple-signing.sh` with dummy values in isolated subprocess environments, not repository secrets. Dev builds remain ad-hoc and do not map Apple settings. Forks need no Apple credentials; their release preflight passes with empty settings. Existing non-Apple release requirements still apply. Locally exported Apple configuration is deliberately checked even for dev packaging, so clear it for an ad-hoc build.

Future production secrets should be scoped to a protected release environment with required approvers and trusted tag/repository checks, never supplied to PR code, `pull_request_target`, ordinary CI, or dev snapshots. Retain the presence preflight when moving credential storage into that environment; keep secret access limited to the signing job/steps.

## Intended signing order and runtime policy

Before implementing, inventory the **actual assembled bundle** and recheck Sparkle's pinned-version distribution guidance. The current Sparkle 2.10.0 framework includes `Versions/B/Autoupdate`, `Updater.app`, and `XPCServices/Downloader.xpc` and `Installer.xpc`. Do not modify the downloaded SwiftPM artifact in place: work on its copy inside `dist/Conure.app`.

Sign inside out, using the project Developer ID Application identity and secure timestamps:

1. Finish all compilation, copying, plist changes, embedded update keys, and other bundle mutations.
2. Sign `Contents/Helpers/conure` with Hardened Runtime (`codesign --options runtime --timestamp --sign …`). The app's runtime/entitlements do not automatically apply to a separately launched CLI.
3. Handle Sparkle's deepest code first: its loose `Autoupdate` executable, nested `Updater.app`, and Downloader/Installer XPC bundles (and any deeper code introduced by a future dependency version). Follow Sparkle's signing guidance and preserve each helper's required entitlements, including Downloader's sandbox/network permissions; do not apply the host's entitlements wholesale.
4. Sign the enclosing `Sparkle.framework` after its children. The intended paid design re-signs the embedded framework with the project's identity so host library validation can remain enabled. Validate the pinned framework's compatibility before adopting this policy.
5. Sign the outer `Conure.app` last, applying Hardened Runtime and the host's reviewed entitlements. Signing the app signs its main executable; avoid subsequently rewriting it or any sealed resource.
6. Verify each nested code object, then run `codesign --verify --deep --strict --verbose=2` on the whole bundle. Inspect certificate chain, team identifier, timestamp, runtime flags, and entitlements explicitly: signature integrity alone does not establish that Developer ID signing occurred.

Do **not** use `codesign --deep` to sign recursively. It is appropriate here for verification, not for selecting entitlements or ordering signing operations. Do not strip vendor helper entitlements or re-sign nested code after its parent has been sealed.

Hardened Runtime is not App Sandbox. Keep the host and CLI unsandboxed for this migration: they read user-selected media, write transcripts and model caches, download models, launch subprocesses, and use Sparkle. The CLI installer invokes `/usr/bin/osascript` with administrator consent to create a symlink; validate that flow too. Sandbox adoption would be a separate feature with file-access and helper design changes.

Start with no extra host/CLI entitlement grants. CoreML/ANE, AVFoundation file decoding, and ordinary networking do not by themselves justify JIT, unsigned-executable-memory, audio-input, automation, or sandbox network/file entitlements in this unsandboxed design. There is no microphone-recording feature. Test both speech-swift and FluidAudio under Hardened Runtime with downloaded models. Keep `com.apple.security.get-task-allow` absent/false; do not add `allow-jit`, `allow-unsigned-executable-memory`, or `disable-library-validation` speculatively. Any exception must be narrowly scoped to the executable that demonstrably needs it, security-reviewed, and validated. In particular, decide Sparkle re-signing/library-validation policy against its current guidance rather than silently disabling library validation for the whole app. No production entitlement files are introduced by this preparation change.

## Intended notarization and final artifact order

The future workflow should use two submissions so both the extracted app and the distributed DMG receive stapled tickets:

1. After signing/verification, create a temporary notarization ZIP of `Conure.app` with `ditto -c -k --keepParent`. Submit it using `xcrun notarytool submit … --key <temporary-p8-path> --key-id … --issuer … --wait --output-format json`.
2. Check the returned status is **Accepted**; a submission ID or command completion alone is not success. On rejection/timeout/service error, stop; retrieve `notarytool log` for controlled diagnostic review. Do not expose credentials in diagnostic artifacts.
3. Run `xcrun stapler staple` and `xcrun stapler validate` on `Conure.app` (not the temporary ZIP). Reverify signatures. The app now has its offline notarization ticket.
4. Build and verify the DMG from that stapled app, retaining the current read-only mount, bundle comparison, and Applications-link checks. Sign the DMG with the Developer ID Application identity and a secure timestamp.
5. Submit the signed DMG to `notarytool --wait`, require **Accepted**, then staple and validate the DMG. Notarizing only the DMG must not be assumed to staple the enclosed app.
6. Verify the final DMG's signature and Gatekeeper assessment (`spctl --assess --type open --context context:primary-signature`). Mount it read-only and verify the enclosed app signature, stapled ticket, and `spctl --assess --type execute` result. Gatekeeper success is a **paid-path** requirement; existing ad-hoc releases must not be made to pass it.
7. Only now run `scripts/make-update.sh` for stable versions, then compute SHA-256 and GitHub provenance attestation, upload artifacts, and create the existing draft release. Stapling changes bytes, so no notarization, stapling, re-signing, or other mutations may occur after Sparkle archive/feed signing, checksums, or attestation.

Apple code signatures, notarization tickets, Sparkle update signatures, and GitHub attestations serve different purposes; retain all relevant verification layers. Notarization is automated malware/security checking, not App Store review or a guarantee of safety.

## Enablement checklist (separate reviewed change)

- Establish project ownership/governance and obtain real, project-controlled credentials; configure protected release access and cleanup without exposing secrets to untrusted code.
- Implement explicit paid-mode signing, per-executable entitlement handling, temporary keychain lifecycle, notarization, ticket validation, and final-artifact ordering. Moving the configuration guard alone is not sufficient. Preserve and test the default ad-hoc path.
- Extend the configuration tests to the future policy table, including credential import/team/expiry failures, signing and notary rejection/timeout, cleanup, and refusal to publish on any failure.
- Validate a real Developer ID build through manual workflow dispatch before enabling tag releases. Keep dispatch artifact-only; use the existing version input, not a source-version edit or fake published tag.
- On a clean macOS 15+ Apple Silicon account/VM, test a quarantined download's first launch without a Gatekeeper bypass, offline launch with stapled tickets, bundled and symlink-installed CLI, model download/removal, all ASR engines, diarization, transcript writes, long-file performance, and Sparkle helper installation/relaunch.
- Test upgrading from an existing ad-hoc updater-enabled release to the signed release with the **same Sparkle key**, then signed-to-signed updates. Verify cancellation/failure preservation and no regressions in Conure Dev isolation. Follow [release validation](README.md) and [update validation](updates.md).
- Record evidence for app/DMG signatures, expected team, runtime/entitlements, Accepted submissions and stapled tickets, Gatekeeper assessments, final feed/archive signatures, checksums, and attestation. Do not record private keys or passwords.
- Only after that evidence passes review, enable the paid option and update user-facing signing/Gatekeeper claims. Keep no-credential ad-hoc builds available; leave tag stamping and draft publication unchanged.

## Verification available without membership

Run `scripts/test-apple-signing.sh` for exhaustive absent/partial/complete dummy-configuration checks, invalid modes, value-redaction checks, and rejection through both packaging entrypoints. Run `bash -n scripts/*.sh` for shell syntax. A normal `scripts/make-app.sh <version>` followed by `scripts/make-dmg.sh <version>` verifies the unchanged ad-hoc path locally; `swift build` and `swift test` remain credential-free.

These checks do **not** validate real certificate import, Hardened Runtime entitlements, Apple notarization, stapling, or Gatekeeper acceptance. Those remain deliberately unimplemented and must be verified before paid-path enablement.

## References

- [Apple: Developer ID](https://developer.apple.com/developer-id/)
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Apple: Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-macos)
- [Sparkle: distributing your app](https://sparkle-project.org/documentation/)
- [GitHub: installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
