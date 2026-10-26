# Signed in-app updates

The go/no-go evaluation behind this design — threat model, publisher key lifecycle, installation scenarios, rollback behaviour, and trade-offs — is recorded in [`validation/updates-evaluation.md`](updates-evaluation.md). This document is the operator guide.

## Design

Conure uses Sparkle 2.10.0 for archive validation, extraction, replacement, authorization, and relaunch. A custom `SPUUserDriver` provides the SwiftUI states: checking, current, available with notes, downloading with cancellation/progress, verifying/preparing, ready, and installing. Download and Quit & Install are separate user decisions. No automatic checks, downloads, installation, or system profiling are enabled.

The app pins the official GitHub Releases appcast URL and only accepts newer stable semantic versions whose archive is exactly `https://github.com/nethbotheju/Conure/releases/download/vVERSION/Conure-VERSION.dmg`. Drafts are not publicly accessible. Prerelease releases do not receive an appcast and are marked as prereleases by CI. Sparkle performs system compatibility checks; Conure additionally requires a successfully signed feed and an application (not package) installation. Both signed-feed validation and pre-extraction archive validation are mandatory, with no feed-signature expiration fallback.

This deliberately does not implement a shell script that replaces its own running bundle. Sparkle's signed helper processes handle this, including permissions. Existing helper signatures are preserved when embedding Sparkle in our ad-hoc-signed app. Conure has no Hardened Runtime library validation or sandbox entitlement to bypass.

Installing checks for queued/running jobs and ongoing model changes. Main app/settings controls are disabled during the quit/install handoff. The queue is not persisted; a busy app must finish/cancel work first. Closing or cancelling the update window sends Sparkle a cancellation, using `.skip` at the ready-to-install stage rather than `.dismiss` (which would allow installation on a later quit). If the user quits normally during an update, the application delegate cancels that quit, cancels Sparkle's session, then reissues quit after the cycle finishes. Returning `terminateLater` here can block Sparkle's pending main-queue cancellation callbacks, so it is deliberately not used. Cancellation intent persists across callback gaps; cancellation during extraction waits for the next safe callback, then cancels installation. A deliberate Quit & Install allows Sparkle's termination/relaunch flow.

## One-time publisher setup

Do this **before the first updater-enabled stable release**. These are publisher operations, not end-user installation steps. The key must remain consistent across all releases. Never put a private signing key in the repository or a chat message.

1. Resolve the pinned Sparkle dependency with `swift package resolve`.
2. Generate a dedicated signing identity in your macOS login Keychain:

   ```bash
   TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
   "$TOOLS/generate_keys" --account com.conure.updates
   ```

3. Set the repository **Actions variable** `CONURE_UPDATE_PUBLIC_KEY` to the public key (only the base64 value, not the plist/XML output). To avoid copying it incorrectly:

   ```bash
   PUBLIC_KEY=$("$TOOLS/generate_keys" --account com.conure.updates -p)
   gh variable set CONURE_UPDATE_PUBLIC_KEY --body "$PUBLIC_KEY"
   ```

4. Export the private key to a restricted temporary file and upload it directly to the repository **Actions secret** `SPARKLE_PRIVATE_KEY`, without displaying it:

   ```bash
   (
     umask 077
     KEYDIR=$(mktemp -d -t conure-update-key)
     trap 'rm -rf "$KEYDIR"' EXIT
     KEYFILE="$KEYDIR/private-key"
     "$TOOLS/generate_keys" --account com.conure.updates -x "$KEYFILE"
     gh secret set SPARKLE_PRIVATE_KEY < "$KEYFILE"
   )
   ```

5. Back up the Keychain signing identity securely outside this checkout. Ad-hoc code signing cannot recover trust if this update key is lost. Losing it requires users to manually install a new trusted app; do not silently rotate the public key or disable verification. A compromised key requires a separate incident/recovery plan.

The public key is embedded by `scripts/make-app.sh` from `CONURE_UPDATE_PUBLIC_KEY`. Stable tag builds require it; the signed-feed step also requires the private key. Local bundles without the public key and all Conure Dev bundles disable in-app updates. For a local stable bundle with the real public key, set `CONURE_UPDATE_PUBLIC_KEY` before running the build script. Never embed a throwaway test key in a distributed release.

## Release workflow

The existing tag-driven workflow stamps versions; do not edit `ConureVersion.swift` by hand.

For a stable tag, CI builds the app with the public key, packages and verifies the DMG, produces a concise release summary from commits since the preceding tag, and runs `scripts/make-update.sh`. Sparkle's `generate_appcast` creates and signs the appcast, embeds plain-text release notes, and signs the final DMG. The private key is passed on stdin, never in command-line arguments. `sign_update --verify` verifies the feed; `scripts/verify-update.swift` independently checks the archive signature against the public key, exact URL/version/type metadata, and archive size. This catches mismatched publisher keys before publication.

The final unchanged DMG is checksummed and attested as before. The workflow attaches the DMG, checksum, and signed `appcast.xml` to a **draft** GitHub Release. Only publishing that draft makes it reachable by the updater. Never modify an appcast or DMG after signing. Release-note edits on GitHub do not rewrite the signed in-app summary; regenerating that summary requires signing the feed again. Do not publish a stable release missing its appcast or mark an older release as latest, since the updater uses GitHub's latest-stable asset redirect. Draft publishing remains a human step.

Prerelease tags produce a prerelease draft without an appcast. Manual dispatch builds an artifact, not a published update. Dev builds never publish a stable feed and never embed its signing key. GitHub Actions variables/secrets must be configured by the publisher; this code does not create a production key or modify repository settings.

## Verification

`swift test` covers strict stable semantic versions, fail-closed build configuration, official archive URL policy, signed-feed requirements, explicit two-step consent, busy-work protection, progress, cancellation (including callback gaps), and current/error states. These unit tests do not contact GitHub or replace an installed app.

Run `scripts/test-updates.sh` for disposable feed/archive signing tests, including rejection of wrong-key signatures and tampering. Run `scripts/test-updates.sh --install` in a logged-in macOS session for the full disposable replacement/relaunch test. CI runs this integration mode as well. It compiles the real update policy/store into a tiny harness with a separate test bundle identifier, uses an ephemeral key (not Keychain/publisher secrets), and serves signed fixtures only on loopback. A test-only updater factory supplies the local transport while forwarding validation and lifecycle callbacks to the shipping store. It verifies normal quit before the check callback, quit during extraction, cancel-and-quit at the ready stage (all preserve the old app), and explicit install/relaunch (replaces only the temporary test app). No production app, real GitHub release, speech model, or publisher setting is touched.

Before distributing the first updater-enabled version, also validate the visible UI and real publisher artifacts on a disposable macOS account/VM or copies of test apps, not your working installation:

- Build two stable-version bundles stamped through the packaging scripts with a dedicated **test-only** key and versioned signed archives, or use the disposable harness above. Do not weaken the shipping official-feed policy or publish fake stable versions.
- Verify framework embedding with `otool -L`, bundle signatures with `codesign --verify --deep --strict`, and the appcast/archive with the provided verification tools.
- Confirm a current-version check shows the current state; an available update shows version and summary without downloading yet.
- Download, check progress, cancel, retry; disconnect the network and exercise rate-limit/service failure responses.
- Tamper with the feed, archive, and archive signature separately. Each must be rejected without replacing the existing app. Repeat with a wrong key, wrong repository URL, prerelease, downgrade, and a mismatched archive version/bundle identifier.
- Close the window after download and quit normally. Confirm the original app remains installed. Repeat cancellation during extraction and confirm there is no pending install-on-quit.
- Attempt Quit & Install with active/queued transcription and model downloads; it must not quit or lose work.
- With no outstanding work, choose Quit & Install. Confirm the app quits, the new bundle replaces it, the new app relaunches exactly once, and model/transcript storage is unchanged.
- Exercise insufficient space, read-only/DMG/translocated launch locations, unwritable Applications folders, and cancelled authorization. Confirm clear failure and preservation of the existing app.
- Verify Conure Dev and unpackaged builds never start stable update checks.

The disposable integration test exercises Sparkle's real installer helpers, signed archive verification, replacement, cancellation, and relaunch. It does not validate GitHub publication, the visible SwiftUI window, permission prompts on other accounts, or production publisher-key provisioning. Those release checks remain necessary.

## References

- [Sparkle setup/security](https://sparkle-project.org/documentation/)
- [Programmatic/SwiftUI setup](https://sparkle-project.org/documentation/programmatic-setup/)
- [Publishing and signing updates](https://sparkle-project.org/documentation/publishing/)
- [Updater configuration](https://sparkle-project.org/documentation/customization/)
- [Custom user-driver API](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUserDriver.html)
