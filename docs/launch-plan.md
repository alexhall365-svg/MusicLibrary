# Launch plan: cover the £79 in 2–3 months

**Goal:** about **30 Pro sales** in the first 2–3 months. That covers the £79 developer fee, with nothing earned from the choir and prices far below the competition.

## Principles
- **The choir never pays.** Members use the TestFlight version, which is free. On the App Store, everything a choir member needs (library, reader, annotations, setlists, receiving shared choir music) is free forever.
- **Charge only for librarian power tools.** People who manage big collections pay once, at a fraction of competitors' prices.
- **No subscriptions, no ads, no data collection.**
- **Free Pro for chosen people** with Apple offer codes (see `docs/app-store-setup.md`, App Store section, step 4). Choir members on TestFlight get it free anyway.

## Pricing

| | This app | forScore (iPad leader) |
|---|---|---|
| Download | **Free** | about £25 (US$24.99) up front |
| Extras | **Pro: £3.99 once** | forScore Pro about £15 a year (US$14.99) |
| First-year cost for a power user | **£3.99** | about £40 |

That's roughly **90% cheaper** than forScore in year one, and far cheaper than subscription apps such as Newzik's paid plans. Check competitors' current UK prices on the App Store before launch.

**Free:** import, library, search and browse, reader, annotations, setlists, choir sharing (when built), and editing details by hand.

**Pro (£3.99 once, for life):** Apple Intelligence auto-labelling, bulk labelling with Claude (export and import), Find Duplicates, and future bulk tools (backup and restore, batch edits).

### The maths
- £3.99 includes 20% VAT, which leaves £3.33. Apple then keeps 15% (Small Business Program), so **you receive about £2.83 per UK sale**. US sales ($3.99) come to roughly the same.
- **28 sales ≈ £79.** The target is **30**.
- Apple pays monthly, about 33–45 days after the end of each sales month, so month-3 sales arrive in month 4.
- Tax (check for yourself; this isn't tax advice): the UK £1,000 trading allowance generally means income this small needs no tax return.

---

## Month 1: choir beta and getting store-ready

**Week 1**
- [ ] Enrol in the Developer Program and complete `docs/app-store-setup.md` Steps 1–9.
- [ ] Claude: first TestFlight build. Fix anything the first run shows.
- [ ] Invite the choir through the public TestFlight link. Ask for feedback with TestFlight screenshots.

**Week 2**
- [ ] Claude: fixes from choir feedback.
- [ ] Claude: **Backup and restore**, so nobody loses their library. Pro.
- [ ] Decide the final app name. Claude drafts the store description and keywords.

**Weeks 3–4**
- [x] Claude: the **Pro unlock** (StoreKit 2, one-time purchase, Restore Purchase button, Family Sharing).
- [ ] Claude: **choir sharing** through a shared folder (free), so choir members get the music.
- [ ] Screenshots: run the **Screenshots** workflow on GitHub (iPhone and iPad, demo library) or take your own on the devices.
- [ ] Accept the Paid Apps Agreement, add bank and tax details, and apply for the Small Business Program.
- [ ] Submit to the App Store.

## Month 2: launch (target 15 sales)

**Launch week**
- [ ] App goes live. Post in the places church and choral musicians gather, following each group's self-promotion rules:
  - Reddit: r/choralmusic, r/churchmusic, r/organ, r/musictheory (where allowed).
  - Facebook groups for church musicians, organists and choir directors, and RSCM-affiliated groups.
  - CPDL and IMSLP community forums (in the "tools" sections).
  - Friends in other choirs, the diocese or deanery music newsletter, Making Music members' channels.
- [ ] The pitch: *"Free sheet-music library for iPad. Auto-labels your scores with on-device AI. Pro tools are £3.99 once; no subscription."*
- [ ] Record a 30-second screen recording of importing a pile of scans and watching them label themselves. Post it everywhere.

**Weeks 2–4**
- [ ] Reply to every review and message. Fix the top complaint within a week.
- [ ] Ask happy users (not the choir) for App Store ratings. Claude adds a polite in-app rating prompt, shown once after real use.
- [ ] Check the numbers weekly in App Store Connect → **Trends**.

## Month 3: grow (cumulative target 30 sales)

- [ ] Improve the store listing (keywords such as "forScore alternative", "choir", "setlist", "sheet music", "organ") based on what people search for.
- [ ] Second marketing push with a new feature, e.g. choir sharing, backups or a metronome.
- [ ] If sales are behind target:
  - Add an optional "Buy the developer a coffee" tip (£0.99 or £1.99). The choir is never asked.
  - Release to the EU (declare trader status) and more countries.
  - Promote the iPhone version, which widens the audience.
- [ ] If the choir is a registered charity, consider moving the membership to the charity next year: non-profits can get the fee waived.

## Being realistic
30 sales for a brand-new niche app takes active sharing; it won't happen just by being on the store. The strongest assets are the **free price for the core app**, the **on-device AI labelling** (unusual in this category) and **word of mouth among church musicians**. If month 2 is slow, the month-3 levers above still leave plenty of room, and even without them the app costs only £79 a year to keep running for the choir.
