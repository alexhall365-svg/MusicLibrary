# App Store listing: text to paste

Everything App Store Connect asks for, ready to copy. Character limits are Apple's.

## App information (App Store Connect → Quire → App Information)
- **Name** (30): `Quire: Sheet Music Library`
- **Subtitle** (30): `Scores, setlists & groups`
- **Category:** Music. Secondary: Productivity
- **Content rights:** "No, it does not contain, show or access third-party content". Users import their own PDFs.
- **Age rating:** answer "None" or "No" to every question, giving **4+**.
- **Copyright:** `© 2026 Alex Hall`

## Version 1.0 (App Store tab → 1.0)
**Promotional text** (170, can be changed any time without review):
> Your whole music library on iPad and iPhone. Labels itself with on-device Apple Intelligence. Share music and markings with your choir, band or orchestra.

**Description** (4000):
> Quire keeps all your sheet music in one place, ready for rehearsal and performance.
>
> YOUR LIBRARY
> • Import PDFs from Files, other apps, or a whole folder at once
> • Titles, composers, catalogue numbers, voicing, keys and genres, filled in automatically with Apple Intelligence, privately on your device
> • Search and browse by composer, genre, voicing or tag
> • Finds duplicates, even when the files differ
>
> READING AND MARKING UP
> • Turn pages with a tap or swipe; two pages side by side in landscape
> • Pen and highlighter for Apple Pencil or finger, kept separate from the PDF
> • Setlists for services and concerts, played straight through in order
>
> SHARED GROUPS
> • Share music and lists with a choir, band or orchestra by sending one link
> • Everyone keeps a full copy, so it works offline at rehearsal
> • The director's markings appear on everyone's music; members' own markings stay private
> • Remove a piece and it's removed for everyone
>
> ICLOUD SYNC
> • Your library, setlists and markings stay in step on iPad and iPhone
> • Stored in your own iCloud; works fully offline
>
> PRO, ONCE, FOR LIFE
> The library, reader, markings, setlists, sync and joining a group are free. A one-time Pro unlock adds Apple Intelligence labelling, hosting a shared group, and Find Duplicates. No subscription, no ads, no tracking.

**Keywords** (100, comma-separated, no spaces needed):
`sheet music,score,pdf,choir,band,orchestra,setlist,annotate,music reader,organ,church,rehearsal`

**Support URL:** `https://github.com/alexhall365-svg/MusicLibrary`
**Privacy Policy URL:** `https://github.com/alexhall365-svg/MusicLibrary/blob/claude/jolly-volta-19ra5m/docs/privacy-policy.md`

**What's New** (not shown for 1.0, only later versions).

## App Privacy (App Store Connect → App Privacy)
- "Do you or your third-party partners collect data from this app?" → **No, we do not collect data from this app.**
- Why: no analytics, ads or accounts. Libraries are stored on the device and in each user's own iCloud, which the developer can't access.

## In-app purchase (In-App Purchases → `pro_unlock`)
- **Type:** Non-consumable. **Price:** £4.99. **Family Sharing:** on.
- **Display name:** `Quire Pro`
- **Description** (55): `Auto-labelling, shared groups and duplicate finder`
- **Review screenshot:** a screenshot of the Pro screen (sidebar → Unlock Pro).
- **Review notes:** "Unlocks Apple Intelligence labelling (on supported devices), hosting a shared group, and Find Duplicates."

## App Review information (version page → App Review Information)
- **Sign-in required:** No.
- **Contact:** your name, phone and email.
- **Notes:**
> No account is needed. To try the app, import any PDF (Files, or share a PDF to Quire).
>
> Pro (one-time in-app purchase "pro_unlock") unlocks Apple Intelligence labelling, hosting a shared group, and Find Duplicates. Use Unlock Pro in the sidebar; Restore Purchase is on the same screen. Apple Intelligence labelling needs a device with Apple Intelligence enabled; elsewhere the app says it's unavailable and everything else works.
>
> iCloud & Groups (sidebar → Tools): sync uses the user's own iCloud (CloudKit). Hosting a shared group needs Pro and an iCloud account; members join by tapping a share link in a second Apple Account. Members see the owner's markings on group music but can't change them.

## Export compliance
"Does your app use encryption?" is already answered by the build (only Apple's standard encryption, `ITSAppUsesNonExemptEncryption` = NO). If asked: **None of the algorithms mentioned above**.
