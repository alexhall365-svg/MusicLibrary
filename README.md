# Music Library

A personal iPad and iPhone app for cataloguing, annotating and performing from PDF sheet music, with Claude-assisted bulk labelling. "Music Library" is a working name: rename it in `Config/App.xcconfig`.

## What it does (version 0.1)

- **Library:** import PDFs from Files, the share sheet ("Open in Music Library"), drag and drop, or a whole folder. Duplicates are skipped by content hash. The library has a grid or list view, search (ignores case and accents), sorting, and browsing by composer, genre, voicing and tag.
- **Details:** title, composer, catalogue number, voicing/instrumentation, key, genre, tags and notes, plus your own custom fields.
- **Reader:** full-screen pages with tap-zone or swipe page turns, two pages side by side in landscape, a page scrubber, performance mode (locks out annotation) and resume where you left off. Upcoming pages are rendered ahead of time.
- **Annotation:** Apple Pencil or finger, with pen, highlighter, eraser, colours, undo and redo. Annotations are stored separately; the original PDF is never changed.
- **Setlists:** create, reorder and play straight through from one piece to the next.
- **Label with Claude:** export scores with text read from their first pages (on-device OCR for scans), have Claude fill in the details, then paste or open Claude's reply. You review every change, with low-confidence fields highlighted, before it's saved. See [docs/claude-labelling.md](docs/claude-labelling.md).

See [ROADMAP.md](ROADMAP.md) for what's next.

## Project layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec. The Xcode project is generated from it, not committed. |
| `Config/App.xcconfig` | **App name, bundle ID and version: the one place to change them.** |
| `MusicLibrary/` | App source: `Model`, `Storage`, `Import`, `Exchange` (JSON format), `Reader`, `Views` |
| `MusicLibraryTests/` | Unit tests: metadata model, file-name parsing, JSON exchange, matching, import, setlists |
| `docs/` | Install guide, metadata schema, Claude labelling guide |
| `.github/workflows/ci.yml` | Builds and tests on GitHub's Macs on every push; can also build an installable `.ipa` |

## Building

### On GitHub (no Mac needed)
Every push runs the tests on a macOS runner. To get an installable app:
**Actions → CI → Run workflow** (leave "build_ipa" ticked). When it finishes, download **MusicLibrary-unsigned-ipa** from the run's Artifacts. Then follow [docs/installing.md](docs/installing.md).

### On a Mac with Xcode 15 or later
```sh
brew install xcodegen
xcodegen generate
open MusicLibrary.xcodeproj
```
Choose your iPad as the run destination. Under **Signing & Capabilities**, pick your Personal Team, then press Run (⌘R).

Command-line tests:
```sh
xcodebuild test -project MusicLibrary.xcodeproj -scheme MusicLibrary \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' CODE_SIGNING_ALLOWED=NO
```

## Data and privacy
Everything stays on the device, in the app's Application Support folder: `Library.store` (database), `Scores/` (PDF copies) and `Annotations/`. That folder is included in the iPad's own iCloud/Finder device backup. The app makes no network requests.
