# Going live: TestFlight and the App Store, all from an iPad

The whole setup takes about an hour of tapping, spread over a few days while Apple approves things. Do the parts in order. **⏸** marks a wait.

You need: your iPad, your Apple ID (with two-factor authentication on) and a payment card. A laptop is optional; it only makes Part 4 easier.

---

## Part 1: Join the Apple Developer Program (£79/year)

1. Install **Apple Developer** from the App Store and open it.
2. Tap **Account** and sign in with your Apple ID.
3. Tap **Enroll Now** and choose **Individual**.
4. Follow the prompts: confirm your legal name and address, then scan your photo ID (passport or driving licence) with the iPad camera.
5. Pay the £79 with in-app purchase.
6. **⏸** Wait for the "Welcome to the Apple Developer Program" email. It's usually under 48 hours.

## Part 2: Choose the name and bundle ID

1. **App name:** what people see on the App Store. It must be unique on the store, up to 30 characters, and you can change it later.
2. **Bundle ID:** a permanent, reverse-domain identifier such as `uk.yoursurname.choirlibrary`. Use lowercase letters, numbers and dots only. **It can never change** after the first upload.
3. **Tell Claude both.** I'll update the code so the name is consistent everywhere.

## Part 3: Create the app in Apple's systems (Safari)

### 3a. Register the bundle ID
1. In Safari, go to **developer.apple.com/account** and sign in.
2. Open **Certificates, IDs & Profiles → Identifiers** and tap **+**.
3. Choose **App IDs**, then **Continue** → **App** → **Continue**.
4. **Description:** your app name. **Bundle ID:** choose **Explicit** and type the exact ID from Part 2.
5. Leave all capabilities unticked. Tap **Continue** → **Register**.

### 3b. Note your Team ID
- Go to **developer.apple.com/account** → **Membership details**.
- Copy the **Team ID**, a 10-character code like `AB12CD34EF`. Keep it in Notes.

### 3c. Create the app record
1. Go to **appstoreconnect.apple.com** (or use the **App Store Connect** app) → **Apps** → **+** → **New App**.
2. Fill in:
   - **Platforms:** iOS.
   - **Name:** your app name.
   - **Primary language:** English (UK).
   - **Bundle ID:** pick the one you registered.
   - **SKU:** anything, e.g. `choirlibrary001`.
   - **User access:** Full Access.
3. Tap **Create**.

## Part 4: Let GitHub upload builds (the API key)

This is the fiddliest part. A laptop makes it easier, but the iPad is fine.

### 4a. Create the key
1. In App Store Connect, go to **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**.
2. If asked, tap **Request Access** and accept.
3. Tap **+** (Generate API Key). **Name:** `GitHub`. **Access:** **Admin**. Admin is needed so GitHub can create signing certificates for you.
4. Copy the **Issuer ID** (shown above the list) and the new key's **Key ID** into Notes.
5. Tap **Download API Key**. You can only do this **once**, and Safari saves the `.p8` file to **Files → Downloads**.

### 4b. Copy the key's contents
- **On iPad:** open Files → Downloads, long-press the `AuthKey_XXXX.p8` file → **Rename** and change `.p8` to `.txt`. Open it, then **Select All → Copy**. It starts with `-----BEGIN PRIVATE KEY-----`.
- **On a laptop:** open the file in Notepad and copy everything.

### 4c. Add the key to GitHub
1. In Safari, open your repository on github.com. Tap **Settings** (use the **⋯** menu on a narrow screen) → **Secrets and variables** → **Actions**.
2. On the **Secrets** tab, add three repository secrets with **New repository secret**:
   - `ASC_KEY_ID`: the Key ID.
   - `ASC_ISSUER_ID`: the Issuer ID.
   - `ASC_KEY_P8`: paste the whole key text, including the BEGIN and END lines.
3. On the **Variables** tab, add two repository variables:
   - `APP_BUNDLE_ID`: your bundle ID from Part 2.
   - `APPLE_TEAM_ID`: your Team ID from 3b.
4. Delete the `.p8`/`.txt` file from Downloads. GitHub keeps it encrypted, and nobody (including Claude) can read it back.

## Part 5: The first build

1. On GitHub: **Actions** → **TestFlight** → **Run workflow** → **Run workflow**. You can also just ask Claude to run it.
2. **⏸** About 15 minutes for the green tick, then 5–15 minutes of processing at Apple.
3. If it goes red, tell Claude. First runs often need a small fix, and Claude can read the logs.

## Part 6: TestFlight for you and the choir

### 6a. You (internal testing)
1. Install **TestFlight** from the App Store.
2. In App Store Connect, go to your app → **TestFlight** → **Internal Testing** → **+**. Name the group `Me` and add yourself.
3. Turn on **automatic distribution**, so every new build reaches you.
4. Accept the email invitation on your iPad, then install from TestFlight.

### 6b. Choir and friends (external testing)
1. Go to **TestFlight** → **External Testing** → **+**. Name the group `Choir`.
2. Fill in **Test Information**: a short description, your email, and a privacy policy URL (Part 7).
3. Add your build to the group and submit it for **Beta App Review**. **⏸** This usually takes under a day.
4. Turn on the group's **Public Link** and share it. Members install TestFlight, tap the link, and install the app. It's free for them.
5. To release a later build to the choir: open the Choir group → **Builds** → **+**, pick the build, and add "What to Test" notes (Claude will write them for you).

## Part 7: Privacy policy page (free)

The App Store and external TestFlight both need a public privacy policy link.
1. Go to **gist.github.com** (signed in) and choose **Create public gist**.
2. Filename: `privacy-policy.md`. Paste the text from `docs/privacy-policy.md` in this repository.
3. Tap **Create public gist** and copy the page's address. That's your privacy policy URL. You can use the same page as the support URL, or make a second gist.

## Part 8: The App Store (when you're ready to sell)

Do this once the choir has used the TestFlight version for a few weeks. The launch plan has the timing.

1. **Agreements:** in App Store Connect → **Business**, accept the **Paid Apps Agreement**. Add your bank account, and fill in the tax form: as a UK individual this is usually the W-8BEN, which certifies you aren't a US taxpayer.
2. **Small Business Program:** apply at developer.apple.com/app-store/small-business-program. It cuts Apple's commission from 30% to **15%**.
3. **In-app purchase:** Claude will add the "Pro" unlock to the app. In App Store Connect → your app → **In-App Purchases** → **+**, create a **Non-Consumable** with the product ID Claude gives you and set its price.
4. **Store listing:** in your app → **App Store** tab. Add screenshots (take them on the iPad, and the iPhone if it's supported), the description and keywords (Claude will draft them), the privacy page, the age rating questionnaire (4+), and **App Privacy** ("Data Not Collected").
5. **Countries:** under **Pricing and Availability**. Selling in the EU means declaring yourself a "trader", and your contact details are then shown publicly on EU store pages. If you'd rather not, leave EU countries unticked at first.
6. Pick the build and tap **Add for Review** → **Submit**. **⏸** Usually 1–2 days.

---

## Day-to-day after setup
- Ask Claude for a change. Claude builds and tests it, then runs **TestFlight** and the new build reaches your "Me" group automatically.
- Happy with it? Add the build to the Choir group (Part 6b, step 5), or submit it to the App Store (Part 8, step 6).
- A monthly automatic build keeps TestFlight from expiring.
