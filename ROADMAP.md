# Roadmap

## ✅ Phase 1: core app (v0.1)
- [x] Library: import (Files, share sheet, drag and drop, folders), duplicate detection, grid/list, search, sort, browse by composer/genre/voicing/tag
- [x] Metadata: title, composer, catalogue no., voicing, key, genre, tags, notes, custom fields
- [x] Reader: tap/swipe turns, two-up landscape, pre-rendering, page scrubber, performance mode, resume position
- [x] Annotation: pen, highlighter, eraser, colours, undo/redo, Pencil-only or finger; stored separately from the PDF
- [x] Setlists: create, reorder, play through
- [x] Bulk labelling with Claude: export with page text/OCR, forgiving import, review screen, folder packages
- [x] Versioned JSON exchange format (`docs/metadata-schema.md`)
- [x] CI build and tests on GitHub; unsigned .ipa for sideloading
- [x] Runs on iPad alone via Swift Playgrounds (`MusicLibrary.swiftpm`)
- [x] Find Duplicates (name, text and first-page similarity) with safe deletion
- [x] Apple Intelligence labelling: automatic on import, relabel existing scores with review, per-score fill-in

## Next: going public (see docs/launch-plan.md)
- [x] Signed TestFlight/App Store pipeline (GitHub Actions), privacy manifest, privacy policy
- [x] Pro unlock (one-time £3.99, product ID `pro_unlock`): AI labelling, Claude bulk tools, duplicates; backup to follow
- [x] iPhone layout (compact reader controls, two-page view only where it fits)
- [x] Demo library and Screenshots workflow for App Store images
- [ ] App Store listing, screenshots, rating prompt

## Planned: iCloud sync and choir sharing (see docs/icloud-and-choir-plan.md)
- [ ] Local-first iCloud sync across your own devices (CloudKit / CKSyncEngine); full local copies always, works offline
- [ ] Shared Choir Library with lists (e.g. "Christmas season 2026"), editors, read-only members, removals propagate
- [ ] Annotations private per person (synced across own devices); live shared annotations later
- [ ] Pricing: own sync free; hosting a Choir Library is Pro; receiving is free

## Idea: downloadable score packs (see docs/score-packs-plan.md)
- [ ] Ready-labelled public-domain packs (e.g. Bach Organ Works, Evensong Essentials), bought once or included with Pro; no subscription
- [ ] Packs reuse the existing folder/package import; rights checked per file (public domain in the UK/EU, or a licence that allows selling)

## Phase 2
- [ ] **Share library with friends:** export a "share package" (selected scores or a setlist, PDFs + metadata.json, optionally annotations) that a friend imports with the existing folder/package import. Later, a live shared library via iCloud (needs a paid account).
- [ ] **Backups (high priority while running in Swift Playgrounds):** one-file export/import of everything (database, `Scores/`, `Annotations/`) through Files/Google Drive. All user data already lives under one folder (`LibraryPaths.root`), so this is mostly zipping it.
- [ ] Export an annotated copy of a PDF (flattened)
- [ ] Polish from device testing

## Later
- [ ] Face-gesture page turns (ARKit/TrueDepth), off by default
- [ ] Bluetooth page-turn pedals (arrow/page keys)
- [ ] Half-page turns, crop margins, bookmarks and repeat/D.S. jump links
- [ ] Annotation text boxes, stamps (dynamics, breaths, fingering) and layers
- [ ] Metronome and pitch pipe
- [ ] Optional Anthropic API key (stored in the Keychain) as another `MetadataSuggester`, for in-app Claude labelling
- [ ] Finding public-domain scores (IMSLP, CPDL), reusing the import package and respecting each site's terms
- [ ] iCloud sync between iPad and iPhone (paid developer account; the models are already CloudKit-compatible)
- [ ] Automatic Google Drive backup
- [ ] App Store readiness: rename, final bundle ID, privacy manifest, licence review
