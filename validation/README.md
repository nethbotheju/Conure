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
the run. Point `CONURE_LIBRARY_DIR` at a temporary folder while testing records so
release runs do not pollute the real library.

## Checks

| # | Check | Command | Expected |
|---|---|---|---|
| C1 | Default model, all formats | `transcribe short.wav --speakers A,B`, `--timed --unique`, `--format srt --unique` | Correct names; timed MD has `[h:mm:ss]`; SRT blocks numbered, timed, speaker-prefixed |
| C2 | Compressed container | same on `.m4a`/`.mp4` | Transcript matches the WAV run |
| C3 | Unified EN | `--model parakeet-unified-en` | Capitalization and punctuation reviewed |
| C4 | Multilingual + hint | `--model parakeet-v3-multilingual --language fr` | Correct French incl. accents |
| C5 | Japanese auto-detect | `--model parakeet-v3-multilingual` (no hint) | Japanese script, not romaji |
| C6 | Speakers 2/3/4 | `--diarize`, then `--speaker-count` 1/2/3/4 | One stable label per voice; no drift; a count below the detected clusters merges weak voices and reports it in the done/progress detail; strong extras are kept |
| C7 | Long file, every engine | each model on the ~2 h file, `--speakers --timed` | Completes; < 4 GB peak RSS; record wall time + RSS |
| C8 | Cancel (SIGTERM) | `kill -TERM` mid-run | Exit 130; no partial or modified output |
| C9 | Cancel (SIGINT) | `kill -INT` mid-run | Exit 130; no output file |
| C10 | Collision policy | run twice without `--replace`/`--unique`; export twice to the same path | Second run refused, existing file untouched; exports overwrite only the destination file, never the record |
| C11 | Model manager | `models list` / `download` / `remove` | States, sizes, engine tags correct; required models non-removable |
| C12 | GUI smoke | `swift run ConureApp` | Single window: Upload (⌘N), Queue (⌘1), Library (⌘2), Settings (⌘,); drop-anywhere and Finder **Open With** land in Upload; a finished job's **Open** switches to Library and selects the record |
| C13 | Media import | follow [`media-import.md`](media-import.md) on the packaged app | Drag-and-drop and Finder **Open With** reach the job configuration sheet |
| C14 | Record round trip | `transcribe short.wav --diarize --save --no-export`, inspect `~/Library/Application Support/Conure/library/`, `speakers <record> --json`, `speakers <record> --set 1=Alice`, `export <record> --format md --timed` | Schema v1 record with metadata/speakers/lines; no audio copied; rename persists and export shows the new name; record unchanged by export |
| C15 | Library CLI errors | `speakers <record> --set 9=X`, `--set 1=`, edit `schemaVersion` to 9, corrupt a JSON file, then `conure speakers`/`export` | Clear errors, no partial writes, library still lists readable records; newer schema refused |
| C16 | App Library flow | packaged app: Upload → add → transcribe → open → rename → export → delete | Record listed newest first with speaker names; rename updates every line and survives relaunch; blank/newline/overlong names rejected; export Save panel defaults to the source folder and title; delete asks for confirmation and moves only the record to the Trash; a moved source still opens and exports; `Conure Dev` uses `Conure Dev/library`; `CONURE_LIBRARY_DIR` overrides both |

## Run records

One file per pass: `runs/<YYYY-MM-DD>-<issue-or-tag>.md`. Include environment,
media characteristics, per-check results, the long-file baseline, limitations
found, and open items. Compare against the previous baseline; investigate >20%
regressions in wall time or peak RSS before tagging.
