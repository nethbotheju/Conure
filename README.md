<p align="center">
  <img src="App/Resources/icon.png" width="140" alt="Conure">
</p>

<h1 align="center">Conure</h1>

<p align="center"><strong>Local-first audio &amp; video transcription for Apple Silicon Macs.</strong></p>

<p align="center">
  <a href="https://github.com/nethbotheju/Conure/actions/workflows/ci.yml"><img src="https://github.com/nethbotheju/Conure/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/nethbotheju/Conure/releases"><img src="https://img.shields.io/github/v/tag/nethbotheju/Conure?label=release" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License"></a>
</p>

NVIDIA's Parakeet ASR running entirely on-device (CoreML / Neural Engine), with speaker diarization, a queue-driven GUI, and a scriptable CLI — one engine behind both.

## Features

- **Fully local:** audio never leaves your Mac, and everything works offline after the first model download.
- **Fast:** the default speech-swift model transcribes at ~45–95× real-time on Apple Silicon; other model speeds vary.
- **Lean:** the default model used ~1.7 GB peak memory in a 2-hour test; FluidAudio long-file memory is still being validated.
- **Speaker-aware:** name up to 4 attendees and every line comes out labeled with the right speaker.
- **App + CLI:** choose a model per job in the queue app or script the CLI with JSON output; both share the same pipeline.
- **Formats:** clean Markdown with optional timestamps, or ready-to-use SRT subtitles with speaker prefixes.

## Install

**Requirements:** macOS 15+ on Apple Silicon (M1–M4). ~860 MB of model downloads on first use (auto-managed).

Conure is open-source (MIT licensed). Both stable Conure and Conure Dev are **ad-hoc signed**, not signed with an Apple Developer ID, and **not notarized by Apple**. An ad-hoc signature records code integrity but does not verify the publisher's identity or mean Apple has reviewed or approved the app. macOS Gatekeeper may therefore block first launch with an unidentified-developer or “Apple could not verify” warning.

### Stable release

1. Download **`Conure-<version>.dmg`** from [this repository's Releases page](https://github.com/nethbotheju/Conure/releases).
2. Open the DMG, drag **Conure** to **Applications**, then eject the DMG.
3. Follow [First launch and Gatekeeper](#first-launch-and-gatekeeper) below. Once the app opens, required models (~240 MB) download automatically; the selected transcription model downloads on first use.

### Check for updates

Choose **Conure → Check for Updates…**. The update window shows **You’re up to date** when appropriate, or the newer stable version and release notes. Choose **Download Update**, wait for signature verification and preparation, then choose **Quit & Install**. Conure quits, Sparkle replaces the app, and Conure reopens. Finish or cancel queued/running transcriptions and model operations first: the queue is not saved across restarts. Models and transcripts are not replaced. Cancelling or closing the update window cancels the update rather than scheduling installation on a later quit.

Updates use [Sparkle](https://sparkle-project.org), pinned in SwiftPM. Both the feed and update archive must be signed with the publisher’s Ed25519 update key. Verification is required **before extraction**, even though the app itself is ad-hoc signed. No paid Apple Developer membership is required for this update-signing mechanism; it does not make the app notarized or Apple-approved. A build without the publisher’s public key clearly disables in-app updates instead of accepting an unsigned replacement.

Checks happen only when requested, never automatically at launch or on a schedule. Sparkle fetches `https://github.com/nethbotheju/Conure/releases/latest/download/appcast.xml`; GitHub redirects this to the latest published non-prerelease release asset and may use its asset CDN. Downloads require an explicit button press and start at the matching official repository’s versioned DMG asset. The feed is cryptographically verified, including the embedded plain-text release summary; external release-note downloads are disabled. No app-provided authentication or system profiling is used. GitHub/CDN servers receive normal network metadata (including IP address and Sparkle’s app/version User-Agent). No recordings, transcripts, file paths, or model inventory are sent. Sparkle stores downloaded update data in its local cache until installation or cleanup. Browser links use your browser’s normal GitHub session/privacy settings.

Only signed, newer stable semantic versions with the expected official Conure DMG URL are accepted; draft releases are inaccessible and prereleases are excluded from the stable feed. Downgrades, other repositories, package installers, and unsigned feeds/archives are refused. Network errors, malformed feeds, signature failures, disk/permission failures, and incompatible system versions produce messages rather than claiming the app is current. Sparkle handles extraction, privileged installation when necessary, replacement, and relaunch; no shell-based self-replacement is used. If running from a DMG or an app-translocated/read-only location, move Conure to Applications first. Transcription remains usable offline.

**Conure Dev**, prerelease, and unpackaged builds make no stable update requests and never replace stable Conure. Dev snapshots remain manual GitHub Actions artifact installs. Older releases without an updater require one manual installation of an updater-enabled release. Publisher signing-key setup and release/upgrade testing are documented in [validation/updates.md](validation/updates.md).

### Development builds (Conure Dev)

Development builds are snapshots of `main` for testing, not stable releases. They are published as GitHub Actions artifacts, not on the Releases page, and expire after 14 days.

1. Sign in to GitHub and find a successful **Dev build** run for `main` in [GitHub Actions](https://github.com/nethbotheju/Conure/actions/workflows/dev-build.yml). Download its `Conure-Dev-YYYYMMDD-SHA` artifact.
2. Extract the outer artifact download to find `Conure-Dev-YYYYMMDD-SHA.zip`.
3. Extract the inner ZIP and move **Conure Dev.app** to **Applications**. Follow the first-launch steps below using **Conure Dev** instead of **Conure**.

Conure Dev runs its own bundled CLI and stores models in `~/Library/Application Support/Conure Dev/models/`, separate from stable Conure and the standalone CLI. Both apps can coexist. To uninstall the dev build, remove `/Applications/Conure Dev.app`; optionally delete that dev models folder to reclaim its storage.

### Verify a download

New stable DMGs and development ZIPs include a `.sha256` file and a GitHub artifact attestation. Older builds may not have attestations or embedded build metadata. Verify the **original DMG or inner dev ZIP**, not the outer GitHub artifact download or an extracted app.

For a stable release, download the DMG and its matching `.dmg.sha256` from the same release. In their folder, substitute the release version and full source commit shown in the release notes:

```bash
VERSION="0.2.0"
SOURCE_COMMIT="paste-the-full-source-commit-from-the-release-notes"
shasum -a 256 -c "Conure-$VERSION.dmg.sha256"
gh attestation verify "Conure-$VERSION.dmg" \
  --repo nethbotheju/Conure \
  --signer-workflow nethbotheju/Conure/.github/workflows/release.yml \
  --source-ref "refs/tags/v$VERSION" \
  --source-digest "$SOURCE_COMMIT" \
  --deny-self-hosted-runners
```

For a development build, extract the outer artifact download, then verify the inner ZIP before extracting it. Replace `NAME` with the actual filename without `.zip`:

```bash
NAME="Conure-Dev-YYYYMMDD-SHA"
shasum -a 256 -c "$NAME.zip.sha256"
gh attestation verify "$NAME.zip" \
  --repo nethbotheju/Conure \
  --signer-workflow nethbotheju/Conure/.github/workflows/dev-build.yml \
  --source-ref refs/heads/main \
  --deny-self-hosted-runners
```

Use a recent [GitHub CLI](https://cli.github.com/) with `gh attestation verify` support; authenticate with `gh auth login` if requested. Verification must succeed and identify the expected repository, workflow and run. Do not treat a missing or failed attestation as success. Attestations are published to GitHub's attestations API (supported for this public repository), and linked in the workflow summary; they are not Apple signatures.

After installation, open **Settings → About** (or **About Conure** / **About Conure Dev** from the app menu). Use **Copy Diagnostics** for a plain-text support report containing app and bundled CLI versions (with a mismatch warning), commit/build run, macOS/chip, and model IDs, engines, and readiness. It excludes transcripts, recording names, job details, file paths, environment variables, and source refs. **Refresh** rechecks versions and model state without downloading or loading models. Unpackaged builds or missing CLIs show unavailable values.

The About view displays the full source commit, source ref (the tag for stable releases), version and link to the packaging run recorded in the signed app bundle. Compare them with the stable release notes or the dev run's **Source commit** summary and triggering successful CI run. For `workflow_run` dev builds, GitHub's attestation source identity describes the **packaging workflow revision**, which can be newer than the CI commit checked out for compilation. The checked-out commit is recorded inside the attested ZIP's app metadata and in the run summary; do not assume those two revisions are identical.

Checksums detect corruption but do not authenticate their own origin. Attestations bind the artifact digest to a GitHub Actions identity/run, not to Apple's approval, the safety of the code, or independently reproducible output. **Reproducible builds have not been established.** Local builds record their checkout's commit/ref but may contain uncommitted edits and have no GitHub run or attestation. Unpackaged `swift run` builds display unavailable metadata.

Before publishing, workflows check app identity, embedded source metadata, bundled CLI execution and ad-hoc signatures. Stable packaging also verifies and mounts the DMG read-only, rechecks the enclosed app, and compares it with the assembled bundle. These integrity checks do not replace the [manual release validation](validation/README.md).

### First launch and Gatekeeper

Only approve an app you intentionally downloaded from this repository and whose source you trust.

1. In Finder → **Applications**, **right-click (or Control-click) Conure → Open**. If macOS offers an **Open** confirmation, confirm it.
2. If that does not allow opening (including on macOS 15+), dismiss the warning, then open **System Settings → Privacy & Security**. Scroll to **Security** and click **Open Anyway** next to the message about Conure being blocked. This option appears after an attempted launch and is available for about an hour. Authenticate if requested, then confirm **Open**. This is an exception for this app, not a global change to Gatekeeper.

If macOS reports that the app **will damage your computer**, or that it is **damaged**, stop rather than bypassing the warning. Re-download the app from this repository; if it persists, [report the exact message](https://github.com/nethbotheju/Conure/issues). Do not disable Gatekeeper globally.

## Quick start

**App** — launch Conure, hit **＋**, drop in files (optionally name up to 4 speakers), and watch the queue run.

**CLI** — install the bundled engine on your PATH from Settings, or use it straight from a build:

```bash
# Plain transcript (Markdown, no timestamps) next to the input file
conure transcribe meeting.mp4

# Speaker-labeled Markdown with timestamps and attendee names
conure transcribe meeting.mp4 --speakers "Alice,Bob" --timed

# SRT subtitles with speaker prefixes
conure transcribe recording.m4a --speakers "Alice,Bob" --format srt

# Multiple files (processed sequentially), custom output folder
conure transcribe *.mp4 --speakers "Alice,Bob,Carol" --output ~/transcripts

# Existing transcripts are never silently overwritten — pick a policy:
conure transcribe meeting.mp4 --replace   # overwrite existing output
conure transcribe meeting.mp4 --unique    # write "meeting 2.md" instead

# Progress as JSON lines (for tooling); --pretty for humans
conure transcribe talk.wav --pretty

# Punctuated English or multilingual transcription (models download on first use)
conure transcribe meeting.mp4 --model parakeet-unified-en
conure transcribe french.wav --model parakeet-v3-multilingual --language fr
```

| Flag | Default | Description |
|---|---|---|
| `--model` | `parakeet` | Model id or HuggingFace repo |
| `--language` | auto | Optional script hint for multilingual v3 (e.g. `fr`); Japanese auto-detects without a hint |
| `--speakers` | — | Comma-separated attendee names (max 4); enables diarization |
| `--format` | `md` | `md` or `srt` |
| `--timed / --no-timed` | no | Timestamps in Markdown output (`[H:MM:SS]` per line) |
| `--output` | input folder | Output directory |
| `--replace` | off | Overwrite existing output files |
| `--unique` | off | Write to a numbered filename (`name 2.md`) when the output already exists |
| `--pretty` | JSON lines | Human-readable progress |

### Output collisions

Re-running a transcription never silently overwrites an existing file: by default the CLI stops with an error if the output path is already taken, including when two inputs in the same invocation share a basename and output folder. Pass `--replace` to overwrite or `--unique` to write a numbered copy (`meeting 2.md`) that keeps the correct extension. The queue app performs the same check when jobs are added and asks whether to replace, keep both, or cancel. Output files are always written atomically after the destination is resolved.

## Models

```bash
conure models list                 # registry, download status, sizes (also --json)
conure models download parakeet    # pre-download (~611 MB)
conure models download parakeet-unified-en
conure models download parakeet-v3-multilingual
conure models remove parakeet      # free disk space
```

Models live in `~/Library/Application Support/Conure/models/` (override with `CONURE_MODELS_DIR`). FluidAudio weights are stored in its `FluidAudio/` subfolder, downloaded through the SDK and removable with `conure models remove`. Missing models download automatically on first use. `models list --json` includes the owning `engine`.

| Id | Purpose | Size | Removable |
|---|---|---|---|
| `parakeet` | ASR — Parakeet TDT 0.6B v2 English, CoreML INT8, Neural Engine (default) | ~611 MB | Yes |
| `parakeet-unified-en` | FluidAudio Unified EN, punctuated and capitalized | ~590 MB | Yes |
| `parakeet-v3-multilingual` | FluidAudio Parakeet TDT v3, 25 European languages + Japanese | ~465 MB | Yes |
| `sortformer` | Speaker diarization (≤4 speakers), used with `--speakers` | ~239 MB | No (required) |
| `silero` | Voice activity detection, used otherwise | ~1 MB | No (required) |

The original `parakeet` remains the default. FluidAudio provides the other two ASR models; Sortformer and Silero remain on speech-swift for every model.

## How it works

1. **Decode** — AVFoundation extracts mono 16 kHz PCM (mp4, mov, m4a, mp3, wav, aac, aiff)
2. **Segment** — with `--speakers`: Sortformer diarization produces speaker turns; otherwise Silero VAD finds utterances. Same-speaker turns merge into ≤25 s chunks
3. **Transcribe** — each chunk through the selected ASR engine; chunk bounds become line timestamps, so a line can never blend two speakers
4. **Write** — Markdown or SRT next to the input (or `--output` dir)

The GUI drives the exact CLI as a subprocess (JSON progress on stdout) — one engine everywhere. Internals and repo layout are documented in [AGENTS.md](AGENTS.md).

## Contributing

Pull requests are welcome.

1. Fork the repo and create a branch using `<type>/<issue>-<slug>` (e.g. `feat/42-add-export`).
2. Open a pull request against `main` describing the change.

Coding agents should follow [AGENTS.md](AGENTS.md) for project structure, conventions, and setup.

### Future Developer ID signing

Apple Developer Program membership is not required to contribute, run CI, or build ad-hoc-signed apps. Developer ID signing and notarization remain **disabled**, even with complete credentials. The [signing and notarization migration plan](validation/signing-and-notarization.md) documents credential purposes, fail-closed configuration checks, nested signing order, and the validation required before enabling a paid release path. Tag-based versioning is unchanged.

## Credits

- [Sparkle](https://sparkle-project.org) (MIT and third-party notices) — secure in-app updates; full notices are included in the app bundle.
- [speech-swift](https://github.com/soniqo/speech-swift) (Apache-2.0) © soniqo — the default inference engine, vendored with a long-file fix at `vendor/speech-swift/`
- [FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0) © FluidInference — Unified EN and multilingual CoreML inference
- Parakeet weights (see each model card for license and attribution; Unified EN: CC-BY-4.0) © NVIDIA; CoreML conversions © their respective publishers
- Sortformer © NVIDIA
- Silero VAD (MIT)

## License

Conure code is released under the [MIT License](LICENSE).
