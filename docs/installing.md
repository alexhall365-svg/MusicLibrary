# Installing on your iPad and iPhone

## Route 0 (iPad only, free): Swift Playgrounds ← start here

No Mac, PC, developer account or 7-day expiry. Swift Playgrounds is Apple's free app for building apps on iPad.

1. **Install Swift Playgrounds** from the App Store on the iPad.
2. **Download the code.** In Safari, sign in to github.com, open the `MusicLibrary` repository, tap **Code → Download ZIP**, and choose **Download**.
3. **Unzip it.** Open the **Files** app → **Downloads** and tap the zip. A folder appears (e.g. `MusicLibrary-claude-jolly-volta-19ra5m`).
4. **Move the app package somewhere permanent.** Inside that folder is **`MusicLibrary.swiftpm`** (it may show as "Music Library" with a Playgrounds icon). Long-press it → **Move** → **iCloud Drive → Playgrounds** (or **On My iPad → Playgrounds**).
5. **Open it.** Tap `MusicLibrary.swiftpm`; it opens in Swift Playgrounds. The first time, Playgrounds builds the app, which takes a minute or two.
6. **Run it.** Tap the **▶︎ Run** button (top of the screen). The app appears on the right. To use it full screen, tap the app preview's **full-screen** button (or drag the divider to the left).
7. Next time, just open Swift Playgrounds and tap **Music Library** under My Apps, then ▶︎.

**What's different in Playgrounds:** the app runs inside Swift Playgrounds rather than having its own Home Screen icon, and other apps' "Open in Music Library" share option isn't available. Use the app's **Import** button to bring in PDFs from Files (including Google Drive and iCloud Drive), and **Choose a JSON File…** or **Paste Claude's Reply** for labelling.

**Getting updates:** download the ZIP again (steps 2–3) and replace the old `MusicLibrary.swiftpm` with the new one (same name, same place). Your scores are stored with the app's ID (`com.example.musiclibrary`), which doesn't change, so they should survive updates. Until backups exist, **try an update with a few test scores before importing your whole collection.**

**Later, a proper Home Screen app:** with a paid Apple Developer membership (enrol in the Apple Developer app on the iPad), Swift Playgrounds can send the app to App Store Connect (**App Settings → Upload to App Store Connect**). You then install it through **TestFlight**, still without a computer.

---

The routes below need a computer once a week to reinstall with a free Apple ID.

## Route A: Sideloadly with the GitHub-built app (works with an older Mac or a Windows PC)

Your 2016 Mac can't run a recent enough Xcode, but it can run **Sideloadly**, which signs the app with your free Apple ID and installs it.

1. **Get the app file.** On github.com, open the repository and go to **Actions → CI → Run workflow**. Choose the branch, keep **build_ipa** ticked, and press **Run workflow**. After about 10 minutes, open the finished run and download **MusicLibrary-unsigned-ipa** under **Artifacts**. Unzip it to get `MusicLibrary-unsigned.ipa`.
2. **Install Sideloadly** from sideloadly.io on the Mac (or PC). On a Mac it may also ask you to install its Mail plug-in; follow its prompts.
3. **Connect the iPad** with a USB cable. Unlock it and tap **Trust** if asked.
4. In Sideloadly, drag in the `.ipa`, type your Apple ID, and press **Start**. Enter your Apple ID password when asked. It is sent only to Apple. Approve any two-factor code.
5. **On the iPad**, turn on Developer Mode: **Settings → Privacy & Security → Developer Mode → On**. The iPad restarts; confirm **Turn On** afterwards. (The option only appears after the first sideload attempt.)
6. **Trust the developer:** **Settings → General → VPN & Device Management →** your Apple ID **→ Trust**.
7. Open **Music Library**.

Repeat steps 3–7 for the iPhone.

## Route B: Xcode (a Mac with macOS 14 or later)

1. Install Xcode from the Mac App Store, open it once and let it install components.
2. In Terminal:
   ```sh
   brew install xcodegen      # needs Homebrew: https://brew.sh
   git clone https://github.com/alexhall365-svg/MusicLibrary.git
   cd MusicLibrary
   xcodegen generate
   open MusicLibrary.xcodeproj
   ```
3. In Xcode, **Settings → Accounts → +** and add your Apple ID.
4. Click **MusicLibrary** at the top of the left sidebar, choose the **MusicLibrary** target, then the **Signing & Capabilities** tab. Set **Team** to "*Your Name* (Personal Team)". If Xcode says the bundle ID is unavailable, change `APP_BUNDLE_ID` in `Config/App.xcconfig` (e.g. `com.yourinitials.musiclibrary`), run `xcodegen generate` again and reopen.
5. Plug in the iPad, pick it from the device menu at the top of the window, and press **▶** (⌘R).
6. Do steps 5–6 from Route A on the device (Developer Mode, Trust).

## The 7-day limit

Apps signed with a free Apple ID stop opening after 7 days. **Your library is not lost:** reinstall the same way (same bundle ID), and the app opens with all your scores, annotations and setlists. Sideloadly can also refresh automatically when the iPad is on the same Wi-Fi as the Mac.

A free Apple ID allows 3 sideloaded apps per device. A paid Apple Developer account (£79/year) removes the 7-day limit, enables iCloud sync and TestFlight, and needs only a team change in Xcode.
