# Quire

An iPad and iPhone app for cataloguing, annotating and performing from PDF sheet music, with on-device Apple Intelligence labelling, iCloud sync and shared groups for choirs, bands and orchestras. The display name and bundle ID live in `Config/App.xcconfig` (and `MusicLibrary.swiftpm/Package.swift` for Swift Playgrounds); the project folders keep their original "MusicLibrary" names.

## What it does (version 0.1)

- **Library:** import PDFs from Files, the share sheet ("Open in Quire"), drag and drop, or a whole folder. Duplicates are skipped by content hash. The library has a grid or list view, search (ignores case and accents), sorting, and browsing by composer, genre, voicing and tag.
- **Details:** title, composer, catalogue number, voicing/instrumentation, key, genre, tags and notes, plus your own custom fields.
- **Reader:** full-screen pages with tap-zone or swipe page turns, two pages side by side in landscape, a page scrubber, performance mode (locks out annotation) and resume where you left off. Upcoming pages are rendered ahead of time.
- **Annotation:** Apple Pencil or finger, with pen, highlighter, eraser, colours, undo and redo. Annotations are stored separately; the original PDF is never changed.
- **Setlists:** create, reorder and play straight through from one piece to the next.
- **Find Duplicates:** groups scores that are the same file, have the same or a similar title, share the text on their first pages, or have a first page that looks the same. You pick which copies to delete; setlist entries move to the copy you keep, and you can mark a group "Not duplicates".
- **Apple Intelligence (iPadOS 26, on device):** new imports are filled in automatically from the first pages of each score, and anything uncertain is marked "Check details" under Needs Details. You can relabel earlier imports from **Auto-Label** (with a review screen), from a score's long-press menu, or with **Fill In with Apple Intelligence** in its details.
- **Shared groups:** share music, lists and the director's markings with a choir, band or orchestra by link. See [docs/group-guide.md](docs/group-guide.md).

See [ROADMAP.md](ROADMAP.md) for what's next.

## Free and Pro
Reading, annotating, the library, setlists and editing details are free. **Pro** (one-time in-app purchase, product ID `pro_unlock`, £3.99) unlocks Apple Intelligence labelling, hosting a shared group and Find Duplicates. Debug builds (Swift Playgrounds) always have Pro.

## Project layout

| Path | What |
| --- | --- |
| `MusicLibrary.swiftpm/` | **The app.** A Swift Playgrounds app package: open it on an iPad in Swift Playgrounds (or in Xcode). |
| `MusicLibrary.swiftpm/Sources/` | App source: `Model`, `Storage`, `Import`, `Exchange` (JSON format), `Reader`, `Views`, `Resources` |
| `project.yml` | XcodeGen spec for CI and Mac builds, using the same sources. The Xcode project is generated, not committed. |
| `Config/App.xcconfig` + `MusicLibrary.swiftpm/Package.swift` | App name, bundle ID and version (keep the two in step). |
| `MusicLibraryTests/` | Unit tests: metadata model, file-name parsing, JSON exchange, matching, import, setlists |
| `docs/` | Install guide, App Store and iCloud setup, group guide, metadata schema |
| `.github/workflows/ci.yml` | Builds and tests on GitHub's Macs on every push; can also build an installable `.ipa` |

## Releasing (TestFlight and App Store)
See [docs/app-store-setup.md](docs/app-store-setup.md) for the one-off iPad setup. After that, the **TestFlight** workflow (Actions → TestFlight → Run workflow) builds, signs and uploads a new version. The plan for covering costs is in [docs/launch-plan.md](docs/launch-plan.md).

## Building

### On an iPad (no computer)
Open `MusicLibrary.swiftpm` in **Swift Playgrounds** and press Run. Step-by-step instructions are in [docs/installing.md](docs/installing.md).

### On GitHub
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
Everything stays on the device (Apple Intelligence runs on the device too), in the app's Application Support folder: `Library.store` (database), `Scores/` (PDF copies) and `Annotations/`. That folder is included in the iPad's own iCloud/Finder device backup. TestFlight and App Store builds also sync it through your private iCloud (CloudKit), and can share a Choir Library with your choir; see `docs/icloud-setup.md` and `docs/group-guide.md`. Otherwise the app makes no network requests.

## Copyright

© 2026 Alex Hall. All rights reserved. This source code is published for reference only and is **not open source**: it may not be copied, modified, redistributed or used to build other apps without written permission. See [LICENSE](LICENSE).

