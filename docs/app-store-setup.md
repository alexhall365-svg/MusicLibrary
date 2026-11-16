# Going live: TestFlight (and later the App Store), all from an iPad

About **45–60 minutes** of tapping, plus Apple's waiting times. Work in order. Keep the **Notes** app open: you'll collect five values along the way.

| Value | Example | Where it comes from |
|---|---|---|
| App name | `Choir Library` | You choose (Step 1) |
| Bundle ID | `uk.yoursurname.choirlibrary` | You choose (Step 1) |
| Team ID | `AB12CD34EF` | Developer website (Step 2) |
| Issuer ID | `69a6de7e-…` (long) | App Store Connect (Step 4) |
| Key ID | `2X9R4HXF34` | App Store Connect (Step 4) |

A laptop is optional. It only makes Step 4 easier.

---

## Step 1: Choose the name and bundle ID (5 min)
- **App name:** what people see in TestFlight and the App Store. It must be unique on the store, up to 30 characters, and can change later. Have a back-up name ready in case your first choice is taken.
- **Bundle ID:** permanent and never shown to users. Use lowercase letters, numbers and dots only, e.g. `uk.yoursurname.choirlibrary`. **It can never be changed** after the first upload, so don't use "musiclibrary" if you might rename the app.

## Step 2: Register the bundle ID and find your Team ID (5 min, Safari)
1. Go to **developer.apple.com/account** and sign in.
2. Scroll to **Membership details** and copy the **Team ID** (10 characters) into Notes.
3. Go to **Certificates, IDs & Profiles** → **Identifiers** → the blue **+**.
4. Select **App IDs** → **Continue** → **App** → **Continue**.
5. **Description:** your app name. **Bundle ID:** keep **Explicit** and type your bundle ID exactly.
6. Leave every capability unticked (iCloud comes in a later phase). Tap **Continue** → **Register**.

## Step 3: Create the app in App Store Connect (5 min)
1. Go to **appstoreconnect.apple.com** (Safari, or the App Store Connect app) → **Apps** → **+** → **New App**.
2. Fill in:
   - **Platforms:** iOS.
   - **Name:** your app name. If it's taken, try your back-up.
   - **Primary Language:** English (U.K.).
   - **Bundle ID:** pick yours from the list. If it's missing, wait a minute and reload.
   - **SKU:** any private reference, e.g. `choirlibrary001`.
   - **User Access:** Full Access.
3. Tap **Create**.

## Step 4: Create the API key that lets GitHub upload (10 min)
1. In App Store Connect, go to **Users and Access** → the **Integrations** tab → **App Store Connect API**.
2. If you see **Request Access**, tap it, accept, and reload.
3. Under **Team Keys**, tap **+** (Generate API Key):
   - **Name:** `GitHub`.
   - **Access:** **Admin**. This is needed so GitHub can create the signing certificates for you.
4. Copy into Notes:
   - the **Issuer ID** (above the keys table);
   - the new key's **Key ID**.
5. Tap **Download API Key** → **Download**. ⚠️ **You can only download it once.** Safari saves `AuthKey_XXXXXXXXXX.p8` to **Files → Downloads**.
6. Copy the key's text:
   - **iPad:** Files → Downloads → long-press the `.p8` file → **Rename** → change the ending to `.txt` → **Done** → tap it to open. Tap and hold → **Select All** → **Copy**. It must include the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.
   - **Laptop:** open the file in Notepad, then Ctrl+A, Ctrl+C.

## Step 5: Give GitHub the settings (10 min, Safari)
1. On **github.com**, open your **MusicLibrary** repository → **Settings**. On a narrow screen it's under the **⋯** menu.
2. In the left menu: **Secrets and variables** → **Actions**.
3. On the **Secrets** tab, tap **New repository secret** three times. Names must match exactly (capitals and underscores):

   | Name | Value |
   |---|---|
   | `ASC_KEY_ID` | Key ID |
   | `ASC_ISSUER_ID` | Issuer ID |
   | `ASC_KEY_P8` | the whole key text from Step 4.6 |

4. On the **Variables** tab, tap **New repository variable** for each:

   | Name | Value |
   |---|---|
   | `APP_BUNDLE_ID` | your bundle ID |
   | `APPLE_TEAM_ID` | your Team ID |
   | `APP_DISPLAY_NAME` | the name under the icon, e.g. `Choir Library` (optional; default "Music Library") |

5. Delete the key file from **Files → Downloads**. GitHub stores it encrypted and nobody can read it back, not even you or Claude. If you ever lose it, revoke the key in App Store Connect and make a new one.

## Step 6: Run the first build (2 min, then about 30 min waiting)
1. In the repository, go to **Actions** → **TestFlight** (left list) → **Run workflow** → **Run workflow**.
2. Wait for the green tick: **about 15 minutes**. Then Apple processes the build for **another 5–30 minutes**. You get an email when it's ready.
3. **If it turns red:** tell Claude "the TestFlight run failed". Claude can read the logs and fix it. First runs often need one small fix.

## Step 7: Install it on your iPad and iPhone (internal testing, 5 min)
1. Install **TestFlight** from the App Store, on both devices.
2. In App Store Connect → your app → **TestFlight** → **Internal Testing** → **+**:
   - **Name:** `Me`.
   - Tick **Enable automatic distribution**, so every new build reaches you.
3. Add yourself as a tester and tap **Invite**.
4. Open the invite email on the iPad (or open TestFlight; it may already show the app) and tap **Install**. Repeat on the iPhone.
5. If App Store Connect ever asks about **export compliance**, answer "None of the algorithms mentioned above". The app already declares this, so it normally won't ask.

## Step 8: Privacy policy page (5 min)
External testers and the App Store need a public privacy policy link.
1. Go to **gist.github.com** (signed in).
2. **Filename:** `privacy-policy.md`. Paste the text from `docs/privacy-policy.md`, replacing `[your contact email]` with an email you're happy to share.
3. Tap **Create public gist**, then copy the page's address into Notes.

## Step 9: Invite the choir and friends (external testing; Apple's check takes up to a day)
1. App Store Connect → your app → **TestFlight** → **External Testing** → **+**. **Name:** `Choir`.
2. Fill in **Test Information** (left menu under TestFlight):
   - **Beta App Description:** e.g. "A sheet-music library for our choir: import PDFs, read, annotate and play setlists."
   - **Feedback Email:** your email.
   - **Privacy Policy URL:** the gist link.
   - **Contact info:** your name, phone and email (only Apple sees this).
   - **Sign-in required:** No.
3. In the **Choir** group → **Builds** → **+** → pick the build → add **What to Test** (Claude can write it) → **Submit for Review**.
4. Once approved (usually within 24 hours), turn on **Public Link** in the group and copy it.
5. Send the link to the choir and friends. On their iPhone or iPad they **install TestFlight**, **tap the link**, then **Install**. It's free, and Pro is free on TestFlight.
6. Later builds: add each build to the Choir group the same way. New builds of the same version usually skip review.

---

## Troubleshooting
| Problem | Fix |
|---|---|
| Run says "Not set up yet. Missing: …" | A secret or variable is missing or misspelt (Step 5) |
| "No profiles" or "No signing certificate" | The API key isn't **Admin**, or the bundle ID in GitHub doesn't exactly match Step 2 |
| "Invalid API key" / 401 | Wrong Key ID or Issuer ID, or the `ASC_KEY_P8` text is missing its BEGIN/END lines |
| "Bundle ID not found" during upload | The app record (Step 3) wasn't created with this bundle ID |
| Build uploaded but not in TestFlight | Apple is still processing; wait for the email (up to 30 minutes) |
| Anything else | Tell Claude; it can read the run's logs |

## Later: the App Store (when you're ready to sell)

Do this once the choir has used the TestFlight version for a few weeks. The launch plan has the timing.

1. **Agreements:** in App Store Connect → **Business**, accept the **Paid Apps Agreement**. Add your bank account, and fill in the tax form: as a UK individual this is usually the W-8BEN, which certifies you aren't a US taxpayer.
2. **Small Business Program:** apply at developer.apple.com/app-store/small-business-program. It cuts Apple's commission from 30% to **15%**.
3. **In-app purchase (Pro):** in App Store Connect → your app → **Monetization → In-App Purchases** → **+**:
   - **Type:** Non-Consumable. **Reference name:** `Pro`. **Product ID:** `pro_unlock` (exactly this).
   - Set **Price** to **£3.99** (UK as the base; Apple suggests the other countries' prices).
   - Turn on **Family Sharing**.
   - Add a display name ("Pro") and description ("Auto-labelling, bulk tools and duplicates, forever").
   - Add the review screenshot: the Pro screen (sidebar → Unlock Pro).
   - Attach it to the app version when you submit.
4. **Codes for free Pro (you, friends, the choir):** Apple's **offer codes** give Pro for free. They can be created once the app is live on the store and the Pro purchase has been approved.
   1. In App Store Connect, go to your app → **Monetization → In-App Purchases → Pro** → **Offer Codes** → **Create Offer Code**.
   2. Choose **Free** and the countries.
   3. Choose the kind of code:
      - **Custom code:** one word you choose, e.g. `EVENSONG2026`. Set a redemption limit (e.g. 25) and an expiry date. Good for a group: share it once.
      - **One-time codes:** Apple generates a list of unique codes, one per person. Good for giving to individuals; download the list and hand them out.
   4. People redeem in the app: **Unlock Pro → Redeem Code**, then type the code. They can also use the App Store app: tap their account picture → **Redeem Gift Card or Code**.
   - Redeemed codes count as a £0 purchase. They work with **Restore Purchase** and Family Sharing like a normal purchase.
   - On **TestFlight**, nobody needs a code: Pro "purchases" there are free test purchases.
5. **Store listing:** in your app → **App Store** tab. Add screenshots for **iPhone (6.9-inch)** and **iPad (13-inch)**: run the **Screenshots** workflow on GitHub, or take them on your devices, the description and keywords (Claude will draft them), the privacy page, the age rating questionnaire (4+), and **App Privacy** ("Data Not Collected").
6. **Countries:** under **Pricing and Availability**. Selling in the EU means declaring yourself a "trader", and your contact details are then shown publicly on EU store pages. If you'd rather not, leave EU countries unticked at first.
7. Pick the build and tap **Add for Review** → **Submit**. **⏸** Usually 1–2 days.

---

## Day-to-day after setup
- Ask Claude for a change. Claude builds and tests it, then runs **TestFlight** and the new build reaches your "Me" group automatically.
- Happy with it? Add the build to the Choir group (Step 9.6), or submit it to the App Store (the App Store section, step 7).
- A monthly automatic build keeps TestFlight from expiring.
