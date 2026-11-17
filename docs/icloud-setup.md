# Setting up iCloud sync and the Choir Library

One-off steps to turn on iCloud for TestFlight builds. Everything here works from **Safari on an iPad**; no Mac is needed. Allow about 30 minutes.

You need: the developer account and TestFlight pipeline already working (see `app-store-setup.md`), and your **bundle ID** and **Team ID** from that guide.

Your iCloud container ID is `iCloud.` followed by your bundle ID, e.g. `iCloud.uk.yoursurname.quire`. (To use a different one, set a repository variable `CLOUDKIT_CONTAINER`.)

## Step 1: Create the iCloud container (5 min)
1. Go to [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, IDs & Profiles** → **Identifiers**.
2. Tap **+**, choose **iCloud Containers**, **Continue**.
3. **Description:** your app name. **Identifier:** `iCloud.` + your bundle ID. **Continue** → **Register**.

## Step 2: Turn on iCloud and push for the app (5 min)
1. Still in **Identifiers**, change the filter (top right) back to **App IDs** and tap your app.
2. Tick **iCloud**, and choose **Include CloudKit support** if asked.
3. Tap **Configure** (or **Edit**) next to iCloud, tick your container from Step 1, **Continue** → **Save**.
4. Tick **Push Notifications** (no certificate is needed: leave its Configure alone). Push lets iCloud tell your devices about changes straight away.
5. Tap **Save** at the top, and **Confirm** if warned that profiles will be regenerated.

## Step 3: Make a CloudKit management token (5 min)
1. Go to [icloud.developer.apple.com](https://icloud.developer.apple.com) and sign in. Tap **CloudKit Database** and choose your container. (It can take a few minutes to appear after Step 1.)
2. Open the account menu (your initials, top right) → **Manage Tokens** (or **Settings → Tokens**).
3. Create a **Management Token**, name it `GitHub`, and copy it straight away: it isn't shown again.
4. In GitHub, open the repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**. Name: `CLOUDKIT_MANAGEMENT_TOKEN`. Paste the token. **Add secret**.

A management token can only change the database's design (record types), never anyone's data.

## Step 4: Upload the database design (5 min)
1. In GitHub → **Actions** → **CloudKit Schema** → **Run workflow** → **Run workflow**.
2. Wait for the green tick (about 2 minutes). This puts the record types from `CloudKit/schema.ckdb` into the container's **Development** environment.

## Step 5: Deploy it to Production (2 min)
TestFlight and App Store builds use **Production**, so copy the design across:
1. In the CloudKit Console, choose your container, then **Deploy Schema Changes…** (in the side menu or the environment menu).
2. Check it lists `AnnotationPage`, `Score`, `ScoreFile` and `Setlist`, then **Deploy**.

Repeat Steps 4–5 only if a future update changes `CloudKit/schema.ckdb` (Claude will say so). Production record types can be added to but never removed.

## Step 6: Build for TestFlight
Run the **TestFlight** workflow as usual. It now:
- builds with iCloud on (`CLOUD_SYNC=YES`),
- signs the app with the iCloud and push entitlements,
- checks the signed app really has them before uploading.

If it fails at "The signed app has no iCloud entitlement", recheck Step 2. To upload a build without iCloud meanwhile, add a repository **variable** `ICLOUD_SYNC` = `off`.

## Step 7: Test
You need two Apple Accounts and two devices for the choir. In TestFlight, install the new build on each.

**Your own devices (same Apple Account):**
1. On the iPad, open **iCloud & Choir** (in the sidebar under Tools). Check **Sync with iCloud** is on and it says "Up to date". The first upload takes a while for a big library; leave the app open on Wi-Fi.
2. On the iPhone, open the app with the same Apple Account. Your scores, setlists and annotations arrive.
3. Edit a score's details, reorder a setlist, draw on a page: each appears on the other device within a minute (bring the app to the front to fetch straight away, or pull down on the sidebar).

**The choir (a second Apple Account):**
1. On your device: **iCloud & Choir** → **Create Choir Library**, name it, then send the invitation by Messages or Mail. To make someone an editor (for example a deputy), choose **Can make changes** for them in Apple's sharing screen; everyone else should be **View only**.
2. On the member's device: install the TestFlight build first, then tap the invitation. The choir appears in the sidebar under its name.
3. On your device: touch and hold a score → **Add to *choir name***, or make a **New Choir List** in the choir's sidebar section and add scores to it. The member's device downloads the music and the list.
4. Remove a score from the choir: it disappears from the member's device.

TestFlight testers must be added in App Store Connect before they can install the app (TestFlight → Internal or External Testing).

## Troubleshooting
| What you see | What to do |
|---|---|
| "Not signed in to iCloud" | Sign in under Settings → [your name] on the device |
| Nothing syncs; status stays "Waiting to sync" | Check Steps 4–5 (schema deployed to Production). Open **iCloud & Choir** to see any error |
| Sharing says it **cannot create type cloudkit.share** | The **CloudKit Schema** workflow tries to add this system type. If its log shows a warning that it couldn't, sharing needs one share made in the Development environment first. Tell Claude: the fallback is a Development build installed on a registered device, which takes a few extra setup steps |
| "Your iCloud storage is full" | Free space in Settings → [your name] → iCloud. Everything stays on the device meanwhile |
| A member sees "View only" but should edit | In **iCloud & Choir** → **Invite and Manage People**, tap them and choose **Can make changes** |
| The same score appears twice after first sync | Two devices imported the same PDF before syncing and one had different details. Use **Find Duplicates** |

## How it works (for reference)
See `docs/icloud-and-choir-plan.md`. In short: the library on each device is the source of truth and works offline. CloudKit (`CKSyncEngine`) sends the differences. Your library lives in your private iCloud; the Choir Library is a separate zone in the owner's iCloud, shared with a `CKShare`. Each person's annotations stay in their own private iCloud.
