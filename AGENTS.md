# AGENTS.md

## Project Overview

Conure is a local-first audio/video transcription app for macOS 15+ (Apple Silicon). NVIDIA Parakeet ASR runs on-device via CoreML on the Neural Engine, with Sortformer speaker diarization (max 4 named speakers) and Silero VAD. Two frontends share one engine: a `conure` CLI and a SwiftUI queue app (the GUI drives the CLI as a JSON-lines subprocess).

Pure SwiftPM project — there is no Xcode project or workspace. Do not create one.

## Repo Layout

```
Sources/ConureCore/     engine library: Audio, Transcriber, Diarizer, Segmenter, Writers, ModelStore, Pipeline, Events, Transcript
Sources/conure/         CLI executable (ArgumentParser); ConureVersion.swift holds the version constant
App/Sources/ConureApp/  SwiftUI app: QueueStore (job runner), CLI (subprocess + line buffering), SetupStore, JobsView, AddJobSheet, SettingsView
App/Resources/          icon-master.png (source of truth), AppIcon.icns, icon.png (generated — never edit by hand)
vendor/speech-swift/    PATCHED local fork of soniqo/speech-swift — see rules below
scripts/                make-app.sh, make-dmg.sh, make-icon.swift
docs/                   plan.md (v1), plan-fluidaudio-v2.md (future second engine), research.md (engine landscape)
Tests/ConureCoreTests/  pure-logic unit tests (no model downloads)
```

## Commands

- Build (debug): `swift build` — builds all three targets
- Build (release): `swift build -c release`
- Test: `swift test`
- Common tasks: `make help` (app, dmg, icon, test, clean)
- Assemble app bundle: `make app` → `dist/Conure.app` (release build, CLI in `Contents/Helpers/`, ad-hoc codesigned)
- Run GUI during development: `swift run ConureApp` (it finds the CLI via `CONURE_CLI_PATH` → bundled → `.build` → `/usr/local/bin`)
- Model storage override for testing: `CONURE_MODELS_DIR=/tmp/some-dir`

## Testing

- `swift test` covers pure logic only (writers, time formatting). Model-dependent behavior is tested manually — keep it that way; 600 MB downloads per CI run are wasteful.
- Manual regression expectations (M-series): 2 h file → ~150 s wall time, ~1.7 GB peak RSS, no speaker-label drift across a 994-line transcript.
- Local test media convention: `/tmp/conure-test/` (conversation.wav, meeting.mp4, stress2h.wav). Create synthetic files with `say` + `afconvert` if missing.

## Code Style

- Swift 6, strict concurrency. UI state lives in `@MainActor` `ObservableObject` stores; subprocess callbacks are `@Sendable` and hop via `Task { @MainActor in … }`.
- Minimal comments — code should be self-explanatory. Do not add narrating comments.
- No comment prefixes of any kind; comments read as normal prose.

## Build & Release

- CI (`.github/workflows/ci.yml`): build + test on every PR and push to `main` (macos-15 arm64).
- Release (`.github/workflows/release.yml`): pushing tag `vX.Y.Z` → injects the version from the tag into `ConureVersion.swift` and the app bundle → builds DMG → **draft** GitHub Release with checksums. Manual `workflow_dispatch` builds a DMG artifact without releasing.
- **Never hand-edit the version.** `ConureVersion.swift` stays `x.y.z-dev`; releases are stamped from tags only.
- The runner toolchain is newer than local Xcode — code must satisfy full strict concurrency (Sendable-safe captures in all `readabilityHandler`/`DispatchQueue.async` closures).

## Vendored speech-swift — read before touching

- Local fork, Apache-2.0, modification notice in `Sources/ParakeetASR/ParakeetASR.swift` header. `Package.swift` references it by path.
- **The patch is load-bearing:** Parakeet decoder/joint networks are pinned `.cpuOnly` because their per-token CoreML loop on ANE/GPU exhausts kernel IOSurface memory on long files (~185 encoder calls). Upstream has no fix; do not "upgrade" or revert this.
- Do not add MLX-based products from the vendor to our targets: SwiftPM never compiles the vendored Metal sources, so `mlx.metallib` can never load (verified — this killed the Qwen3 experiment).

## Hard-won gotchas

- Wrap every CoreML prediction call in an `autoreleasepool` when looping; autoreleased wrappers kill the ANE runtime on long jobs.
- First model load after a path change triggers ANE recompilation (~17 s) — normal, not a hang. Warm loads are <1 s.
- When spawning the CLI as a subprocess, drain BOTH stdout and stderr pipes or the process deadlocks on a full pipe buffer.
- Never give SwiftUI `ForEach` data types an ID-only `==` — it skips re-renders entirely (cost us a frozen-progress bug).
- macOS app icons: the squircle occupies 824/1024 of the canvas (80.5%), centered. Full-bleed icons look oversized next to system icons. Regenerate via `make icon`.
- Timestamps come from segmentation chunk bounds, not token-level alignment — by design, so speaker labels and line times can never disagree.

## Model Registry

Defined in `Sources/ConureCore/ModelStore.swift`. Kinds: `asr` (removable, selectable) vs diarization/VAD (required, non-removable, auto-downloaded on app first launch). Adding a model that runs on speech-swift = one registry entry; anything else needs a new engine (see `docs/plan-fluidaudio-v2.md`).
