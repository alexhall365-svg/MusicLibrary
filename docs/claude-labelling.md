# Bulk labelling with Claude

The app has no built-in AI and needs no API key. You use your normal Claude subscription instead.

## Steps (all on the iPad)

1. **Import** your PDFs: **Import → Import PDFs…** (select many at once) or **Import a Folder or Package…**. The app guesses details from file names like `Composer – Title (BWV 123).pdf`.
2. Open **Label with Claude** in the sidebar.
3. **Export:** leave "Only scores missing details" on, pick "50 per file" and tap **Prepare Export**. The app reads the first two pages of each score, using on-device text recognition for scans. The first time, this can take a few seconds per scan. Each file then appears in the list.
4. **Ask Claude:** tap a file → share to the **Claude** app (or save to Files and attach it). In a **new chat**, attach the file, tap **Copy Message** in the app, paste it into Claude and send. The detailed instructions travel inside the file.
5. **Bring the answer back:** use the copy button under Claude's reply (or under its code block), return to the app and tap **Paste Claude's Reply**. Alternatively, save Claude's JSON as a file and use **Choose a JSON File…**, or open a `.json` file with Music Library from Files.
6. **Review:** every change is listed, old → new. Fields Claude was less than 70% sure of, and anything it flagged, are highlighted. Switch to **Needs Checking** to see only those. Untick a score to skip it, or tap **Edit** to correct it, then tap **Apply**.

Repeat for each file. One file per chat keeps each reply within Claude's output limits; around 50 scores per file works well.

## With Claude Code on a Mac

Put your PDFs and a `metadata.json` in one folder and import the folder; the app matches the entries by file name or hash and shows the same review. The format is in [metadata-schema.md](metadata-schema.md).

## Fixing details later

**Export All Library Details** writes every score's current details (without page text) in the same format. Ask Claude to fix or enrich them ("make all composer names Surname, Forenames"; "add liturgical season tags"), then import the result and review it.

## Conventions Claude is asked to follow
- Composer as **Surname, Forenames** (as IMSLP does), so sorting by composer works.
- Catalogue numbers as `BWV 147`, `K. 618`, `Op. 51 No. 1`.
- Voicing in short form: `SATB`, `SATB + organ`, `SSA`, `Unison + organ`.
- Tags for season/occasion (Advent, Lent, Evensong…), language and "Arrangement".

To change these, edit `MusicLibrary/Exchange/ClaudeInstructions.swift`.
