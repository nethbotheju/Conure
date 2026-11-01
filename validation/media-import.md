# Drag-and-drop and Finder Open With

Manual test for the packaged app (`dist/Conure.app` or `dist/Conure Dev.app`).
Issue #19. Everything here runs on a real desktop session; nothing is scripted in CI.

```bash
swift build -c release && swift test
make app                    # or: make dev-app
open dist/Conure.app
```

Media for the run (never committed, delete afterwards):

```bash
mkdir -p /tmp/conure-import && cd /tmp/conure-import
say -o a.aiff "first recording"
afconvert -f WAVE -d LEI16 a.aiff first.wav
afconvert -f m4af -d aac a.aiff second.m4a
printf 'not media\n' > notes.txt
```

| # | Check | Steps | Expected |
|---|---|---|---|
| I1 | Empty-state drop target | With an empty queue, drag `first.wav` from Finder over the window | Dashed tinted overlay reads "Drop to add audio or video files"; released drag opens the Add Job sheet with `first.wav` filled in |
| I2 | Queue-view drop target | Add one job, then drag `second.m4a` over the list | Same overlay while dragging; sheet opens pre-filled with `second.m4a` |
| I3 | Multi-file drop | Drag `first.wav` and `second.m4a` together onto the window | One sheet, both files listed, `2 file(s) selected`; after **Add to Queue**, jobs appear in path order |
| I4 | Duplicate paths | Drag the same file twice in one drag gesture (select both aliases of the same file if Finder allows, otherwise repeat the drop and compare) | A single-file drop never queues twice; a second, separate drop opens the sheet again rather than silently duplicating |
| I5 | Unsupported item | Drag `notes.txt` (or a folder) onto the window | Alert "No supported files" listing the file(s) and the supported formats; queue unchanged, no sheet |
| I6 | Mixed drop | Select `first.wav` and `notes.txt` together and drop | Sheet opens for `first.wav` with an orange note that `notes.txt` was skipped; **Add to Queue** queues only the media file |
| I7 | Configuration is not bypassed | Any drop from I1–I6 | The Add Job sheet appears every time; transcription never starts without it |
| I8 | Open With, app running | Right-click a media file in Finder → **Open With** → Conure | Existing window comes forward, Add Job sheet pre-filled with that file |
| I9 | Open With at launch | Quit Conure, then right-click → **Open With** → Conure on `first.wav` | App launches, a single queue window appears, and the Add Job sheet opens with `first.wav` |
| I10 | Open With, unsupported type | `open -a "Conure" notes.txt` from Terminal (Conure is not registered for `.txt`, so only reachable this way) | "No supported files" alert; queue unchanged |
| I11 | Bundle declarations | `plutil -p dist/Conure.app/Contents/Info.plist \| grep -A12 CFBundleDocumentTypes` | `LSItemContentTypes` lists only `public.mpeg-4`, `com.apple.quicktime-movie`, `com.apple.m4a-audio`, `public.mp3`, `com.microsoft.waveform-audio`, `public.aac-audio`, `public.aiff-audio`; extensions `aac aif aifc aiff m4a mov mp3 mp4 wav`; role `Editor`, rank `Alternate` |
| I12 | Window behaviour | Open a file from Finder while Conure is already running | No extra blank queue window appears; only the configuration sheet |
| I13 | Sheet cancellation | Open the sheet from a drop, then **Cancel** | Nothing is queued; the next drop still works |

## Notes

- LaunchServices caches document-type claims. After rebuilding the bundle, refresh with
  `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$(pwd)/dist/Conure.app"`,
  then confirm the claim: `… lsregister -dump | grep -A2 "Conure"`. Finder's **Open With** submenu should list Conure.
- A dropped file is accepted by extension and existence (`MediaImport.isSupported`); a corrupt file of a supported type is accepted here and fails later in the decoder with its own error — that is out of scope for this test.
- Automated coverage for ordering, de-duplication, rejection messages, and the bundle/allowed-type parity lives in `Tests/ConureAppTests/MediaImportTests.swift`.
