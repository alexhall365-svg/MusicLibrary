# Plan: downloadable score packs (later phase, not started)

Status: **idea, not agreed or built.** Written on 16 Nov 2026 after a test run that collected about 390 public-domain scores (Bach organ works and Anglican choral music) as import packages. Nothing in the app has changed.

## The idea
Sell ready-labelled collections of public-domain scores, e.g. "Bach Organ Works" or "Evensong Essentials", that download straight into the library. Each score arrives with its title, composer, catalogue number, key, genre and tags already filled in.

## Principles
- **No subscription.** Keep the launch plan's promise: packs are one-off purchases, or come with Pro.
- **Local first.** A pack downloads once and is then an ordinary part of the library: fully offline, annotatable, and never offloaded.
- **Reuse what exists.** A pack is exactly what **Import a Folder or Package…** already accepts: PDFs plus a `metadata.json` in the [exchange format](metadata-schema.md). The download step only fetches and unzips it, then hands the folder to `ImportService.importItems`. Duplicates are skipped by content hash, so a pack never doubles up scores the user already has.
- **Only content we have the right to sell** (see Rights below).

## Decisions to make
| Topic | Options | Leaning |
|---|---|---|
| Pricing | (a) included with Pro; (b) each pack a separate one-off purchase; (c) Pro includes one starter pack, others sold separately | (c): it gives Pro a visible extra without giving everything away |
| Hosting | (a) Apple-hosted background assets; (b) our own storage (cloud bucket or CDN) with signed links; (c) bundled in the app | (a) if it works for the app's minimum iPadOS version, otherwise (b) |
| Pack size | One big pack, or several focused ones (by composer, service or season) | Focused packs of roughly 50–300 MB |
| Updates | Re-download the whole pack, or only new files | Version each pack; the app downloads only files whose hash it doesn't already have |

## Architecture
- **Purchase:** StoreKit 2. Pro stays `pro_unlock`. Each pack gets its own non-consumable product ID, e.g. `pack_bach_organ`.
- **Pack manifest:** a small JSON file per pack: ID, version, title, description, size, number of scores, licence notes, and the list of files with their SHA-256. It's shown in a **Score Packs** screen (Pro section of the sidebar) before buying.
- **Download:**
  - (a) Apple-hosted assets: the system downloads the pack once purchase is confirmed. Nothing to run ourselves.
  - (b) Own storage: the app sends the StoreKit transaction to a tiny endpoint that checks it and returns short-lived signed download links. It needs a little server code, but works on any iPadOS version.
  - Both: resumable background download, progress shown on the Score Packs screen, and a check of each file's SHA-256 before import.
- **Import:** unzip to a temporary folder, run the normal package import, then show the usual metadata review, or skip it for packs because their metadata is curated. Delete the temporary files afterwards.
- **Marking pack scores:** add the tag `Pack: <name>` and an extra field `Source pack` so pack scores can be found and filtered. No new model fields are needed.
- **Re-download and restore:** "Restore Purchases" re-enables downloading. Deleting pack scores is allowed, and the user can download them again at any time.
- **Licence notices:** each pack includes a `LICENCES.txt`. Scores that need attribution (e.g. CC BY-SA from Mutopia) carry it in their notes field.

## Rights (the real constraint)
Downloading for private use and selling are different. A pack may include only:
- **Public domain everywhere we sell:** the composer *and* any editor died more than 70 years ago (UK/EU rule), and the scan is of an old printed edition. Example: the Bach-Gesellschaft volumes (1851–1899).
- **Freely licensed for commercial use:** CC0, Public Domain Mark, CC BY or CC BY-SA, with attribution kept. A CC BY-SA licence passes on to the copy we sell.

**Excluded:**
- Anything marked non-commercial (CC BY-NC…). Many modern typeset editions on IMSLP and CPDL use these licences.
- 20th-century composers who are still in copyright in the UK/EU, even though IMSLP's servers in Canada and the US can host them: e.g. Howells, Vaughan Williams, Dyson, Ireland, Willan, Britten, Sowerby. Check each composer's death date; someone who died in 1946 or earlier is public domain in the UK/EU.
- Files whose licence or editor is unknown.

Selling region by region (e.g. a US-only pack) is possible but adds complexity; avoid it at first.

App Review may ask for proof of rights to paid content. Keep a spreadsheet per pack listing every file's source, edition, editor, licence and death dates.

## How the test packs were built (to repeat later)
These were collected in a Claude Code session on 16 Nov 2026. The scripts weren't kept in the repo, but the method is:
1. **Catalogue:** list the works (BWV numbers, category membership, edition details, copyright field) through the IMSLP MediaWiki API (`imslp.org/api.php`). The API is open for metadata. IMSLP and CPDL **block automated PDF downloads** with a CAPTCHA or bot check; respect that.
2. **Bach organ works:** download the Bach-Gesellschaft volumes 3, 15, 25, 38 and 40 from archive.org (item `bach-gesellschaft-ausgabe`). Split them into one PDF per BWV using the printed page ranges, from IMSLP's `{{BachComplete}}` references and the volumes' own tables of contents. The item's `_page_numbers.json` maps printed pages to scan pages. Covers 212 of BWV 525–771.
3. **Typeset Bach:** Mutopia Project (`mutopiaproject.org`) A4 PDFs. 110 pieces, mostly public domain.
4. **Choral:** archive.org's `imslp` collection, a mirror of about 27,000 IMSLP works. Each item records its IMSLP page as `source`, and its `_imslp-files.json` describes each file, so the full score can be picked over parts or arrangements. It's an older snapshot: only 65 of about 820 chosen Anglican works were there.
5. **Package:** folders plus `metadata.json` with `sha256` for each file, so import matches by content.

For a sellable pack, add a step between 1 and 5: **filter by licence and death dates** using the copyright field already collected in step 1.

## What this needs
- An active Apple Developer account, with in-app purchase products created in App Store Connect (as for `pro_unlock`).
- For hosting option (b): a storage bucket and a small endpoint that checks transactions, plus a running cost (small at these sizes).
- **Privacy wording:** the README and privacy policy say the app makes no network requests. Change them to something like: "The app connects to the internet only to download score packs you've bought. Nothing about you or your library is sent."

## Build order (when we start)
1. **Rights pass and a first pack:** Bach Organ Works (Bach-Gesellschaft plus public-domain Mutopia), with its licence spreadsheet.
2. **Score Packs screen:** shows packs from a bundled manifest, buying through StoreKit and restoring purchases. Test with a StoreKit configuration file.
3. **Download and import:** chosen hosting option, resumable downloads, hash checks, then the existing package import.
4. **Pack tags, licence notices and the privacy wording update.**
5. **More packs:** e.g. Evensong Essentials (public-domain canticles and Preces & Responses), Tudor anthems, Victorian anthems.

## Risks and notes
- **Rights mistakes are the biggest risk.** When unsure, leave a file out.
- Scanned PDFs are large (about 0.2–1 MB per page). Keep packs focused so downloads stay reasonable on mobile data.
- The Bach-Gesellschaft is an old edition, without modern fingering or corrections. Say so in the pack description.
- Sources change over time (e.g. IMSLP's bot check is recent). Keep our own copy of every file we sell; never link to the original sites at download time.
