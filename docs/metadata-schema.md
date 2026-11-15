# Metadata exchange format: version 1

This JSON format is the contract between the app and Claude (or any other tool). The app exports it and imports it, and it is the planned basis for library sharing.

```json
{
  "schema": "music-library-metadata",
  "version": 1,
  "exportedAt": "2026-11-15T20:00:00Z",
  "generator": "Music Library 0.1.0",
  "instructionsForClaude": "…present only in exports for labelling…",
  "scores": [
    {
      "id": "2F1C…-UUID",
      "file": "scan0042.pdf",
      "sha256": "9f86d081884c7d65…",
      "pageCount": 6,
      "text": "Text from the first pages (exports only)",
      "metadata": {
        "title": "Hear my prayer",
        "composer": "Purcell, Henry",
        "catalogueNumber": "Z 15",
        "scoring": "SSATB",
        "key": "C minor",
        "genre": "Anthem",
        "tags": ["Lent", "Evensong"],
        "notes": "",
        "extra": { "Publisher": "Novello" }
      },
      "confidence": { "title": 0.95, "composer": 0.9, "key": 0.5 },
      "flags": ["Key unclear from first page"],
      "suggestedFileName": "Purcell – Hear my prayer (Z 15).pdf"
    }
  ]
}
```

## Fields

| Field | Required | Meaning |
| --- | --- | --- |
| `schema` | no | Always `music-library-metadata`. |
| `version` | no (assumed 1) | Format version. The app refuses files with a newer version than it knows. |
| `scores[].sha256` | one of these three | SHA-256 of the PDF. Tried first when matching. |
| `scores[].id` | ↑ | The app's id for the score. Tried second. |
| `scores[].file` | ↑ | Original file name. Used only when exactly one score has that name. In a folder package, it also says which PDF the entry describes. |
| `scores[].metadata.*` | no | **Omitted or `null` = leave unchanged. `""` = clear.** `tags` replaces the tag list. `extra` is merged key by key. |
| `scores[].confidence` | no | 0–1 per field name, or one number for all fields. Below 0.7 is highlighted for review. `"high"/"medium"/"low"` and percentages are also accepted. |
| `scores[].flags` | no | Notes for the reviewer; any flag highlights the score. |
| `text`, `pageCount`, `suggestedFileName`, `generator`, `exportedAt` | no | Informational; ignored on import. |

## Leniency
To cope with hand-written or chat-generated JSON, the importer also accepts:
- JSON surrounded by other text, e.g. a reply containing a ```` ```json ```` code block;
- a bare array of score entries without the wrapper object;
- metadata fields placed directly on the entry instead of under `metadata`;
- `catalogue`/`catalog` for `catalogueNumber`, and `voicing`/`instrumentation` for `scoring`;
- `tags` and `flags` as comma-separated strings.

## Packages
A folder containing PDFs plus a `metadata.json` is an import package. **Import a Folder or Package…** imports the PDFs (skipping duplicates), then shows the metadata review.

## Changing the format
Additive, optional fields keep `version: 1`. Anything that changes the meaning of existing fields bumps the version. The importer then needs a migration, `MetadataExchangeFile.currentVersion` must be updated, and this document must say what changed.
