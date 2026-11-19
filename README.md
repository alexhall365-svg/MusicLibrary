# Quire

**Sheet music library, reader and shared groups for iPad and iPhone.**

Quire keeps a musician's PDF scores in one place, ready for rehearsal and performance, and lets a director share music, lists and markings with a choir, band or orchestra.

This repository contains the source code of the Quire app, published for reference.

## Features
- **Library:** import PDFs from Files, other apps, drag and drop, or whole folders. Duplicate files are detected automatically. Search, sort and browse by composer, genre, voicing and tag.
- **Automatic details:** titles, composers, catalogue numbers, voicing, keys and genres are filled in with Apple Intelligence, on the device. Every suggestion can be reviewed.
- **Reader:** tap or swipe page turns, two pages side by side in landscape, a page scrubber, a performance mode and resume where you left off.
- **Annotation:** pen, highlighter and eraser for Apple Pencil or finger, stored separately from the original PDF.
- **Setlists:** ordered lists for services and concerts, played straight through.
- **iCloud sync:** the library, setlists and annotations stay in step across a person's devices, stored in their own iCloud and available offline.
- **Shared groups:** a director shares music and lists with a group by link. Members keep full offline copies, see the director's markings, and keep their own markings private. See the [group guide](docs/group-guide.md).
- **Find Duplicates:** identifies copies by file, title, page text or the look of the first page.

The library, reader, annotation, setlists, sync and joining a group are free. A one-time **Pro** purchase adds Apple Intelligence labelling, hosting a shared group and Find Duplicates.

## Privacy
Quire collects no data. There are no accounts, analytics, advertising or tracking. Music and annotations are stored on the device and in the user's own iCloud. See the [privacy policy](docs/privacy-policy.md).

## Support
For help or to report a problem, email **alexhall365@gmail.com**.

## Source code
| Path | Contents |
|---|---|
| `MusicLibrary.swiftpm/` | The app (SwiftUI, SwiftData, PDFKit, PencilKit, CloudKit) as a Swift Playgrounds package |
| `MusicLibraryTests/` | Unit tests |
| `project.yml` | XcodeGen project specification used by CI and release builds |
| `Config/` | App identity, version and privacy manifest |
| `CloudKit/` | CloudKit schema |
| `docs/` | [Group guide](docs/group-guide.md), [privacy policy](docs/privacy-policy.md), [import package format](docs/metadata-schema.md), [maintainer guide](docs/maintainers.md) |

Requires iOS/iPadOS 17 or later; Apple Intelligence labelling requires a device that supports it.

## Copyright
© 2026 Alex Hall. All rights reserved. This source code is published for reference only and is **not open source**. It may not be copied, modified, redistributed or used to build other apps without written permission. See [LICENSE](LICENSE).
