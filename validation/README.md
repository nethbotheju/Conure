# Release Validation

Manual validation pass before tagging a release: every ASR engine, long files,
output formats, languages, diarization, cancellation, and performance numbers
for regression tracking. Runs on-device; never in CI. Private media is never
committed — only results live here.

## Procedure

```bash
swift build -c release && swift test
CLI=$(pwd)/.build/release/conure
"$CLI" models list   # download missing via: "$CLI" models download <id>
```

Media (16 kHz mono) lives outside the repository and is never committed:

- **Genuine (required for sign-off):** real 2/3/4-speaker recordings, varied
  real audio ≥ 1 h, real non-English audio.
- **Synthetic (fallback):** `say` + `afconvert` equivalents of the above; mark
  the run as synthetic — it proves stability, not real-world quality.

Time long runs with `/usr/bin/time -l -o run.time …`. Delete the media after
the run.

## Checks

| # | Check | Command | Expected |
|---|---|---|---|
| C1 | Default model, all formats | `transcribe short.wav --speakers A,B`, `--timed --unique`, `--format srt --unique` | Correct names; timed MD has `[h:mm:ss]`; SRT blocks numbered, timed, speaker-prefixed |
| C2 | Compressed container | same on `.m4a`/`.mp4` | Transcript matches the WAV run |
| C3 | Unified EN | `--model parakeet-unified-en` | Capitalization and punctuation reviewed |
| C4 | Multilingual + hint | `--model parakeet-v3-multilingual --language fr` | Correct French incl. accents |
| C5 | Japanese auto-detect | `--model parakeet-v3-multilingual` (no hint) | Japanese script, not romaji |
| C6 | Speakers 2/3/4 | `--speakers` with 2, 3, 4 names | One stable label per voice; no drift, no phantoms |
| C7 | Long file, every engine | each model on the ~2 h file, `--speakers --timed` | Completes; < 4 GB peak RSS; record wall time + RSS |
| C8 | Cancel (SIGTERM) | `kill -TERM` mid-run | Exit 130; no partial or modified output |
| C9 | Cancel (SIGINT) | `kill -INT` mid-run | Exit 130; no output file |
| C10 | Collision policy | run twice without `--replace`/`--unique` | Second run refused, existing file untouched |
| C11 | Model manager | `models list` / `download` / `remove` | States, sizes, engine tags correct; required models non-removable |
| C12 | GUI smoke | `swift run ConureApp` | Queue, cancel, model picker, reveal output |

## Run records

One file per pass: `runs/<YYYY-MM-DD>-<issue-or-tag>.md`. Include environment,
media characteristics, per-check results, the long-file baseline, limitations
found, and open items. Compare against the previous baseline; investigate >20%
regressions in wall time or peak RSS before tagging.
