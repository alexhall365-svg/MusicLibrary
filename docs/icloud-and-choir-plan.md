# Plan: iCloud sync and choir sharing

Status: **built (steps 1–5), awaiting TestFlight testing.** Agreed with the owner on 16 Nov 2026; built 17 Nov 2026. Setup steps: `docs/icloud-setup.md`. Guide for directors and singers: `docs/choir-guide.md`.

Further decisions (17 Nov 2026):
- A person **hosts one** Choir Library and can **join several**. Each choir is its own zone, so hosting several can be allowed later without changing the data.
- Members can **copy a choir list into their own setlists** to reorder it; choir lists themselves are read-only for members.
- The CloudKit schema is uploaded by a GitHub workflow (`CloudKit Schema`) and deployed to Production in the CloudKit Console, so no Mac is needed.

## Non-negotiable principle: local first
- **Every device always keeps a full local copy** of every PDF it has (its own library and any choir music). Nothing is ever offloaded to the cloud.
- **The app works fully offline.** Changes queue and sync when the device is next online.
- iCloud is a **go-between and backup** (the owner's private, encrypted iCloud storage), never the only copy and never required to open music.
- The on-device database and files stay the source of truth. Sync mirrors them; it never replaces them.

## Decisions
| Topic | Decision |
|---|---|
| Own devices | Full iCloud sync on the same Apple Account (iPad and iPhone): scores, details, setlists and annotations |
| Annotations | Synced across **one person's own devices only**. Never shared with other members. Live shared annotations are a possible later feature. |
| Choir sharing | One shared **Choir Library** (a full library), with setlists and lists inside it such as "Evensong – Advent Sunday" or "Christmas season 2026" |
| Simplicity | Reuse existing pieces: the same Score, Setlist, reader and annotation code. A list is just a setlist. |
| Editors | The owner plus **chosen editors** (e.g. a deputy) can add, remove, reorder and edit details. Everyone else is read-only. |
| Removing music | Removing a score from the Choir Library **removes it from members' devices** too (licensing) |
| Members' devices | All Apple (iPhone or iPad with iCloud), so no Android route is needed |
| Storage | Library under 1 GB, so the free 5 GB iCloud plan is enough. Choir Library content counts against the owner's iCloud storage. The app should show the space used. |
| Pricing | Syncing your own devices is **free**. **Hosting** a Choir Library needs **Pro**. **Receiving** choir music is always **free**. |

## Architecture
- **CloudKit with `CKSyncEngine`** (iOS 17+): Apple's sync engine for a local-first app. It supports the private database (own devices) and shared databases (choir).
  - SwiftData's built-in CloudKit mirroring can't do sharing, so the app keeps SwiftData locally and uses CKSyncEngine to sync.
- **Records** (`CloudKit/schema.ckdb`):
  - `Score`: details. `ScoreFile`: the PDF as a `CKAsset`, a separate record so editing details never re-sends or re-downloads the PDF.
  - `Setlist`: name, notes and the ordered list of score IDs (one record, so a list and its order always arrive together).
  - `AnnotationPage`: one record per page. **Private database only.**
  - Reading position and "last opened" stay on each device.
- **Change tracking:** the app compares the library with a ledger of what was last exchanged (`Sync/SyncLedger.swift`) after every save, and queues the differences. Changes received are written to the ledger first, so they never bounce back.
- **Zones:**
  - `Personal` zone (private database): the user's own library.
  - `Choir` zone (owner's private database, shared with a `CKShare`): the Choir Library. Members see it in their shared database.
- **In the app:** a "Choir" section in the sidebar holding the choir's scores and lists. Each score is either *personal* or *choir*. Editors can move scores into the choir.
- **Downloads:** each choir member's app downloads every choir PDF in full and keeps it, so everything works offline at rehearsal.
- **Members' own data:** annotations on choir scores are stored privately in the member's own `Personal` zone, linked by the score's ID. Members can also keep their own personal library alongside.
- **Invites:** with Apple's share sheet (`UICloudSharingController`), using a link or Messages. Editors get read-write permission; members get read-only.
- **Conflicts:** last writer wins for details and for a list's order. PDFs never conflict because they're immutable.
- **First sync:** if the same PDF was imported on two devices before they first synced, the scores are matched by content hash and merged.
- **Removal:** deleting a choir score deletes the shared record, and members' apps delete their local copy (their private annotations for it are deleted too).

## What this needs
- An active Apple Developer Program membership, plus an **iCloud (CloudKit) container** turned on for the app ID. This is a one-off step in the developer website, and Claude will add instructions.
- It runs through TestFlight, not Swift Playgrounds, which can't use iCloud. Swift Playgrounds builds keep working, just without sync.
- Testing needs two Apple Accounts and at least two devices. It can't be tested in CI, so expect a few rounds of TestFlight fixes.

## Build order (when we start)
1. **iCloud container and entitlements** in the project and the TestFlight pipeline. Settings screen with "Sync with iCloud" (on by default) and the storage used.
2. **Own-device sync:** scores, details, setlists, then annotations. Offline queue, first-sync progress, and deletion handling.
3. **Choir Library (owner side):** create it, move or copy scores into it, choir lists, invite people, make editors. Pro required to host.
4. **Choir Library (member side):** accept an invite, full download, read-only UI, private annotations, removals.
5. **Polish:** sync status indicators, error messages (iCloud full, signed out), and docs for directors and members.
6. **Later, maybe:** live shared annotations (e.g. a "director's markings" layer).

## Risks and notes
- First sync of a large library takes time on slow Wi-Fi. Uploads are resumable and run in the background.
- If the owner's iCloud fills up, choir sync stops until space is freed. The app warns before this happens.
- If a member leaves the share, the choir music is removed from their devices. Their own personal library is unaffected.
