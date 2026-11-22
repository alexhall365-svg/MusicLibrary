# Maintainer guide

How Quire is built, signed, released and configured. Builds run on GitHub Actions; no local Mac is required.

## Repository settings
**Settings → Secrets and variables → Actions**

| Kind | Name | Purpose |
|---|---|---|
| Secret | `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` | App Store Connect API key (Admin access): signing, upload and TestFlight crash reports |
| Secret | `PRO_OWNERS` | iCloud user IDs (comma-separated) that always have Pro. Shown in the app under iCloud & Groups → Sync Details |
| Secret | `CLOUDKIT_MANAGEMENT_TOKEN` | CloudKit management token, used only by the CloudKit Schema workflow |
| Variable | `APP_BUNDLE_ID`, `APPLE_TEAM_ID` | App identity |
| Variable | `APP_DISPLAY_NAME`, `CLOUDKIT_CONTAINER`, `ICLOUD_SYNC` | Optional overrides (defaults: `Quire`, `iCloud.<bundle id>`, `on`) |

## Workflows
| Workflow | Trigger | What it does |
|---|---|---|
| **CI** | Push, pull request | Builds the Swift Playgrounds package and the Xcode project, runs the unit tests |
| **TestFlight** | Manual; monthly | Archives, signs (with iCloud and push entitlements, verified before upload) and uploads to App Store Connect |
| **CloudKit Schema** | Manual | Validates and imports `CloudKit/schema.ckdb` into the Development environment |
| **Screenshots** | Manual | Captures App Store screenshots on iPhone and iPad simulators, optionally with public-domain scores |
| **TestFlight Crashes** | Manual | Prints the technical part of recent TestFlight crash reports (no tester details) |

### TestFlight options
- **Give every tester Pro:** off by default. When off, only `PRO_OWNERS` have Pro, and purchases are blocked in TestFlight builds.
- **Build to submit to the App Store:** allows sandbox purchases so App Review can test the in-app purchase. Do not distribute these builds to testers.

Build numbers are the workflow run number plus 100.

## iCloud (CloudKit)
- Container `iCloud.<bundle id>`, with the iCloud (CloudKit) and Push Notifications capabilities enabled on the App ID.
- Record types are defined in `CloudKit/schema.ckdb`. After changing it, run **CloudKit Schema**, then **Deploy Schema Changes** to Production in the CloudKit Console before releasing a build that uses them. Production schema changes are additive only.
- Design: the on-device SwiftData store is the source of truth. `CKSyncEngine` mirrors it to a private `Library` zone, and each shared group is a separate zone shared with a zone-wide `CKShare` (anyone with the link, read-only). The owner's annotations on group music are stored in the group zone; members' annotations stay in their private zone.

## Release process
1. Merge changes to the default branch (CI must pass).
2. Run **TestFlight** and test the build internally and with external testers.
3. Raise `MARKETING_VERSION` in `Config/App.xcconfig` and `displayVersion` in `MusicLibrary.swiftpm/Package.swift` for each App Store version.
4. Run **TestFlight** with **Build to submit to the App Store** ticked, select that build on the version page in App Store Connect, attach any new in-app purchases, and submit for review.
5. If the CloudKit schema changed, deploy it to Production before releasing.

App Store metadata (description, keywords, review notes, privacy answers) is kept in [app-store-listing.md](app-store-listing.md).

## In-app purchase
Non-consumable `pro_unlock`, Family Sharing on. Pro includes Apple Intelligence labelling, hosting shared groups and Find Duplicates. Offer codes can grant Pro without payment once the purchase is live.

## Troubleshooting
| Symptom | Cause |
|---|---|
| "Not set up yet. Missing: …" | A secret or variable above is missing or misspelt |
| "No profiles" / "No signing certificate" | API key lacks Admin access, or `APP_BUNDLE_ID` doesn't match the App ID |
| "The signed app has no iCloud entitlement" | iCloud capability or container not enabled on the App ID |
| Jobs stay queued, then cancel after 15 minutes | No macOS runner available; re-run the workflow |
| Sync doesn't start on a new install | Check iCloud & Groups → Sync Details → Sync Log |
