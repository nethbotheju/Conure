# Conure

Local-first audio/video transcription for Apple Silicon Macs, powered by NVIDIA's Parakeet ASR running entirely on-device (CoreML / Neural Engine). CLI + GUI sharing one engine.

- **Fast** — ~45–95× real-time on M-series (2-hour file ≈ 2–3 minutes)
- **Lean** — peak memory ~1.7 GB for a 2-hour file (budget: 3–4 GB)
- **Private** — everything runs locally; no audio ever leaves your Mac
- **Speaker-aware** — diarization with your attendee names (up to 4 speakers)
- **Formats** — Markdown (optional timestamps) and SRT

## Requirements

- macOS 15+ on Apple Silicon (M1/M2/M3/M4)
- Xcode 26 / Swift 6.2 to build
- ~750 MB of model downloads on first use (auto-managed, see below)

## Build

```bash
swift build -c release
.build/release/conure --help
```

## Usage

```bash
# Plain transcript (Markdown, no timestamps) next to the input file
conure transcribe meeting.mp4

# Speaker-labeled Markdown with timestamps and attendee names
conure transcribe meeting.mp4 --speakers "Alice,Bob" --timed

# SRT subtitles with speaker prefixes
conure transcribe recording.m4a --speakers "Alice,Bob" --format srt

# Multiple files (processed sequentially), custom output folder
conure transcribe *.mp4 --speakers "Alice,Bob,Carol" --format md --output ~/transcripts

# Progress as JSON lines (for tooling/GUI); --pretty for humans
conure transcribe talk.wav --pretty
```

Options:

| Flag | Default | Description |
|---|---|---|
| `--model` | `parakeet` | Model id or HuggingFace repo |
| `--speakers` | — | Comma-separated attendee names (max 4); enables diarization |
| `--format` | `md` | `md` or `srt` |
| `--timed / --no-timed` | no | Timestamps in Markdown output (`[H:MM:SS]` per line) |
| `--output` | input folder | Output directory |
| `--language` | `en` | Language hint; empty for auto-detect |
| `--pretty` | JSON lines | Human-readable progress |

## Model management

```bash
conure models list                 # registry, download status, sizes (also --json)
conure models download parakeet    # pre-download (~611 MB)
conure models remove parakeet      # free disk space
```

Models live in `~/Library/Application Support/Conure/models/` (override with `CONURE_MODELS_DIR`). Missing models are downloaded automatically on first use; the app downloads the required ones on first launch.

| Id | Purpose | Size | Removable |
|---|---|---|---|
| `parakeet` | ASR — Parakeet TDT 0.6B v2 English, CoreML INT8, Neural Engine (default) | ~611 MB | Yes |
| `sortformer` | Speaker diarization (≤4 speakers), used with `--speakers` | ~239 MB | No (required) |
| `silero` | Voice activity detection, used otherwise | ~1 MB | No (required) |

Only Parakeet models can run on our all-CoreML engine today — other Parakeet variants and multilingual models need CoreML conversions that don't exist yet.

## Output format example

```markdown
# meeting.mp4

- **Duration:** 0:47:12
- **Attendees:** Alice, Bob
- **Model:** aufklarer/Parakeet-TDT-v3-CoreML-INT8-30s

## Transcript

[0:00:12] **Alice:** Alright, let's get started…
[0:02:47] **Bob:** I pushed the fix yesterday.
```

## How it works

1. **Decode** — AVFoundation extracts mono 16 kHz PCM from any audio/video track (mp4, mov, m4a, mp3, wav, aac, aiff)
2. **Segment** — with `--speakers`: Sortformer diarization produces speaker turns; otherwise Silero VAD finds utterances. Consecutive same-speaker turns merge into ≤25 s chunks
3. **Transcribe** — each chunk through Parakeet TDT (30 s CoreML windows); chunk bounds become the line timestamps, so speaker labels and timestamps can never merge two speakers into one line
4. **Write** — Markdown or SRT next to the input (or `--output` dir)

Progress streams as JSON lines on stdout (one object per line): `{"type":"progress","stage":"asr","percent":42.1,"detail":"7/17"}` plus a final `{"type":"done",...}` or `{"type":"error",...}`. The GUI drives this exact CLI as a subprocess — one engine everywhere.

## Architecture

```
Sources/ConureCore/    engine library (audio, ASR, diarization, segmenter, writers, model store)
Sources/conure/        CLI executable
App/                   SwiftUI application (queue UI, add sheet, settings)
vendor/speech-swift/   patched local fork of soniqo/speech-swift (Apache-2.0)
```

The vendored fork pins the Parakeet TDT decoder/joint networks to CPU: their per-token CoreML loop
on delegated units (ANE/GPU) exhausts kernel IOSurface memory on long files. Our transcriber
further wraps every prediction in an `autoreleasepool` — without it, autoreleased CoreML
wrappers accumulate and the Neural Engine runtime dies after ~185 encoder calls.

## License & credits

- Conure code: MIT
- `vendor/speech-swift`: Apache-2.0 © soniqo — https://github.com/soniqo/speech-swift
- Model weights: Parakeet TDT (CC-BY-4.0, NVIDIA), Sortformer (NVIDIA), Silero VAD (MIT)
