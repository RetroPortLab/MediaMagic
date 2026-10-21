# ShelfLife — DVD / VHS / LaserDisc / Vinyl / CD / Game catalogue

A native SwiftUI iPhone app (iOS 17+). Your catalogue is stored in a SwiftData
database inside the app's private folder on the phone — no CloudKit, no App
Groups, no analytics, no third-party libraries. The only network use is the
optional barcode lookup, which you can switch off in Settings.

## What it does
- Catalogue DVD, VHS, LaserDisc, Vinyl, CD and video games, with an Owned list and a Wishlist
- Fields adapt to the format: Director/Artist/Developer, Studio/Label/Publisher,
  platform for games, size and speed for vinyl
- Fields: title, year, director, cast, genre, studio, edition, region,
  PAL/NTSC/SECAM, aspect ratio, runtime, disc/tape count, LaserDisc CAV/CLV,
  barcode, catalogue no., condition, sealed, shelf location, price paid,
  purchase date/shop, 1–5 star rating, notes, cover photo
- Cover photo from the camera or photo library (shrunk to keep the database small)
- On-device barcode scanner (iPhone XS or newer). Scanning a barcode you already
  have tells you straight away — handy at car boot sales and charity shops.
- Online lookup after a scan fills in empty fields, a cover and an estimated value
  (only empty fields — nothing you typed is overwritten). "Update value" on any
  item refreshes its price. Settings shows the estimated total.
- Cover Flow browser (toolbar button): swipe through tilted covers with reflections,
  drag the slider to whizz through, tap the centre cover to open it
- Search, filter by format, sort by title (ignoring "The"/"A"), year, format, value or date added
- Swipe to delete; "Got it" moves a wishlist item into the collection
- Export a full backup (.json, includes covers) or a spreadsheet (.csv) to
  Files → On My iPhone (or a USB drive); restore from the .json backup

## Online lookup services
| Service | Key | Gives you |
|---|---|---|
| UPCitemdb | none (≈100/day) | Title, brand, image, US shop price range — any product |
| MusicBrainz | none | Artist, title, label, cat. no., cover — music |
| Discogs | free personal token | Vinyl/CD/music video details + lowest current sale price |
| OMDb | free key (1,000/day) | Film director, cast, genre, runtime, plot, poster |
| PriceCharting | paid subscription | Retro game details + loose/boxed/new values |

Paste keys into Settings → Online lookup. They're kept in the iPhone Keychain
(this device only). Values are a rough guide: Discogs is the most reliable for
records; for old VHS and LaserDisc there's no good free price source, so
values there come from shop listings and may be missing.

## Privacy / backup
Settings has "Keep out of iCloud Backup", **on by default**. With it on, the
catalogue only exists on the phone, so export a .json backup now and then and
copy it somewhere safe. Turn it off if you'd rather iCloud device backups
include it.

Note: if you pick a cover from Photos and your library uses iCloud Photos,
iOS itself may download the original. The app only stores its own small copy.

## Getting it onto your iPhone
You need a Mac with Xcode 15 or later (free from the Mac App Store) and a
cable or Wi-Fi pairing to the phone. A free Apple ID works; the app then needs
re-installing from Xcode every 7 days. A paid developer account (£79/yr) lasts a year.

### Option A — Xcode only (no extra tools)
1. Xcode → File → New → Project → iOS → App.
   Product name `ShelfLife`, Interface **SwiftUI**, Language **Swift**,
   Storage **None**, leave "Host in CloudKit" unticked.
2. Delete the generated `ContentView.swift` and `ShelfLifeApp.swift`.
3. Drag the eight `.swift` files from the `ShelfLife` folder into the project
   (tick "Copy items if needed").
4. Select the target → **Info** tab → add a row
   `Privacy - Camera Usage Description` = `Used to photograph covers and scan barcodes.`
5. Target → **General** → Minimum Deployments: iOS 17.0.
6. Target → **Signing & Capabilities** → choose your Team (your Apple ID),
   and change the Bundle Identifier to something unique, e.g. `uk.yourname.shelflife`.
   Don't add iCloud or any other capability.
7. Plug in the iPhone, pick it as the run destination, press ▶.
8. First run only: on the iPhone go to Settings → General →
   VPN & Device Management → trust your developer certificate.
   On iOS 16+ also turn on Settings → Privacy & Security → Developer Mode.

### Option B — XcodeGen
```bash
brew install xcodegen
cd ShelfLife
xcodegen          # creates ShelfLife.xcodeproj from project.yml
open ShelfLife.xcodeproj
```
Then do steps 6–8 above (edit `bundleIdPrefix` in project.yml first if you like).

## Files
| File | Purpose |
|---|---|
| `ShelfLifeApp.swift` | App entry; local-only SwiftData store |
| `Models.swift` | `MediaItem` and the format/condition/standard enums |
| `ContentView.swift` | Main list, search, filters, sort, summary, scan-to-check |
| `CoverFlowView.swift` | iPod-style Cover Flow browser |
| `ItemDetailView.swift` | Detail page, "Update value" |
| `ItemEditView.swift` | Add/edit form, lookup button, cover photo, value, star rating |
| `DeviceHelpers.swift` | Barcode scanner, camera, image shrinking, backup exclusion |
| `SettingsView.swift` | Stats & value totals, lookup keys, iCloud-backup toggle, JSON/CSV export, restore |
| `LookupService.swift` | Barcode lookups, result merging, Keychain storage for keys |

## Building with Codemagic (no Mac needed)
`codemagic.yaml` has two workflows.

**ShelfLife — compile + unsigned IPA** (free, no Apple account)
1. Put this folder in a GitHub repo (codemagic.yaml at the top level).
2. Sign in at codemagic.io with GitHub → Add application → pick the repo →
   choose "codemagic.yaml" as the configuration.
3. Start a build of *ShelfLife — compile + unsigned IPA* (it also runs on every push).
4. If it goes green, download `ShelfLife-unsigned.ipa` from the build's Artifacts.
   If it fails, open `build-sim.log` — the `error:` lines are what to fix.
5. Install it with **Sideloadly** (Windows or Mac) or **AltStore**, signing in with
   your free Apple ID. Like an Xcode install, it needs refreshing every 7 days.

**ShelfLife — signed TestFlight build** (needs the paid Apple Developer Program)
1. In App Store Connect create the app with your bundle ID, and set `BUNDLE_ID`
   in codemagic.yaml to match.
2. App Store Connect → Users and Access → Integrations → create an API key (App
   Manager). Add it in Codemagic → Team settings → Integrations, named
   `ShelfLife ASC key`.
3. Generate an RSA key (`ssh-keygen -t rsa -b 2048 -m PEM -f cert_key -q -N ""`)
   and add its contents as secure variable `CERTIFICATE_PRIVATE_KEY` in an
   environment group called `signing`.
4. Push a git tag (or start the workflow manually). The build lands in TestFlight;
   install it from the TestFlight app. Builds last 90 days.
