# Pane for iPhone

The iPhone and iPad app, upstream Cra's ported to Pane on 14 Nov 2026 (UPSTREAM_SYNC.md): what
people see says Pane, while the project, targets and folders keep Cra's names, as on the Mac, so
upstream's later commits still apply. Where the Mac app matches Arc, this one matches Arc Search, Arc's
iOS browser: the same screens, measurements, gestures and motion. What it has and what is
still missing is in [ios-parity.md](ios-parity.md); what is known about Arc Search and where
it was learned is in [arc-search-reference.md](arc-search-reference.md).

## Layout

- `iOS/Cra.xcodeproj` — the Xcode project. It uses synchronized folders, so a file added
  under `iOS/Cra` or `iOS/CraUITests` is in the build without touching the project file.
- `iOS/Cra` — the app, UIKit on WKWebView (iOS requires WebKit, and Arc Search uses it too):
  `App` (delegates, launch options, settings file), `Browser` (the root controller and the
  bottom bar), `Search` (the search sheet and suggestions), `Tabs` (tab store, web view,
  tab switcher, favicons), `Theme`, `AI`.
- `iOS/Support/Info.plist` — the app's Info.plist.
- `iOS/CraUITests` — UI tests that drive the app with real taps in the simulator.
- `Packages/CraCore/Sources/CraCore/Mobile` — the app's decisions and its measured layout:
  `MobileChrome` (search sheet and bottom bar), `MobileTabCarousel` (the tab switcher's
  cards), `MobileSuggestions`, `MobileTabs` (tabs, archive), `MobileSettings`. The layer
  rules in [CLAUDE.md](../CLAUDE.md) apply as on the Mac: a decision that needs no view goes
  in CraCore with a test, and CraCore never imports UIKit.

The app shares CraCore with the Mac app (search engines, typed-address rules, cookie-banner
rules, the sidebar model for synced Spaces). CraCore therefore also builds for iOS 17; the two
pieces that start child processes are Mac-only.

## Identity and signing (Pane)

The bundle identifiers are `uz.pane.ios`, `uz.pane.ios.share`, `uz.pane.ios.widgets` and
`uz.pane.ios.uitests`, signed by team `GWSB8L799B`, the Mac app's Apple Development team. Its own
links are `pane://search`, `pane://voice` and `pane://spaces`.

`GWSB8L799B` is a free Apple team (a Personal Team): Apple gives it no iCloud containers and no App
Groups, and Xcode's profiles for it last 7 days. So, unlike upstream (which shares the Mac's App
ID and its iCloud container `iCloud.dk.kildahl.cra`):

- **Spaces from the Mac** come through a folder in iCloud Drive. On the Mac, Settings ▸ General ▸
  Sync ▸ Use a Folder… picks a folder there; on the phone, Sync with Pane for Mac ▸ I have Pane on
  my Mac ▸ Choose the Folder… picks the same one in Files, kept as a security-scoped bookmark
  (`SyncedSidebar`). The Mac app needs no new entitlement for this. The Mac writes a change within
  a second; the phone asks iCloud Drive for the newest files when it comes to the front, when the
  Spaces sheet opens and on pull-to-refresh (`SyncedSidebar.refresh`), and a file presenter
  (`SyncedSidebar.Watcher`) re-reads them while the sheet is open. The line over the Spaces says
  when the Mac wrote what it shows ("Updated just now", `MobileSpaces.updatedLabel`).
- **The share inbox** is a Keychain item in an access group the app and its share extension both
  claim (`$(AppIdentifierPrefix)uz.pane.ios.shared`; see Share extension below).

With the paid Apple Developer Program the upstream way would work again: an iCloud container
(say `iCloud.uz.pane.browser`) on both App IDs, with a provisioning profile for the Mac app too
(`CRA_PROVISIONING_PROFILE` in scripts/build.sh). Without such a profile, claiming the container
in the Mac app would keep it from launching.

To put the app on an iPhone: connect it (or have it on this Mac's Wi-Fi), unlock it, trust this
Mac, turn on Developer Mode, and run `scripts/ios.sh device`. Xcode registers the app ids on the
team and makes the 7-day profile (`-allowProvisioningUpdates`; Xcode ▸ Settings ▸ Accounts has to
be signed in). After 7 days, run it again.

## Build and run

    scripts/ios.sh run                       # build, install and launch in the simulator
    scripts/ios.sh run -CraDataDir fresh     # with an empty data folder
    scripts/ios.sh shot /tmp/cra.png         # screenshot
    scripts/ios.sh test                      # UI tests; screenshots in build/ios/test-screens
    scripts/ios.sh open                      # show the Simulator window
    scripts/ios.sh device                    # build for the connected iPhone and install it
    swift test --package-path Packages/CraCore --filter Mobile   # the decisions, on the Mac

The simulator boots without a window. `CRA_IOS_SIM` picks the device ("Pane iPhone 17" by
default, created when missing). Xcode only builds for iOS when the iOS platform matching its
SDK is installed: `xcodebuild -downloadPlatform iOS`.

Launch arguments put the app in a state for a screenshot or a test:

| Argument | Effect |
|---|---|
| `-CraDataDir <path>` or `fresh` | A data folder of its own, or a new empty one |
| `-CraOpenURL <address>` | Starts with that page in a tab |
| `-CraType <text>` | Starts with that typed in the search field |
| `-CraSearch NO` | Launches without the search sheet |
| `-CraFakeModel YES` | Canned answers in place of the on-device model |
| `-CraSummarize YES` | Summarizes the first page once it has loaded |
| `-CraSyncDir <folder>` or `demo` | The folder the Mac's sidebar syncs into (in place of the one picked in Files), or a made-up sidebar |
| `-CraFakeVoice <text>` | What voice search hears instead of the microphone |
| `-CraShowVoice YES` | Holds the voice overlay up, for a screenshot |
| `-CraOnboarding YES` | Shows onboarding on a test's data folder |

Writing a UI test (`iOS/CraUITests`): pages are `data:` addresses passed with `-CraOpenURL`, so
no test needs the network. XCUITest drops quotes from launch arguments, so a test page has none
(`<button onclick=alert(1234)>`, not `alert('hi')`), and typed addresses have no spaces
(attributes separated by slashes). Web content changed by script does not reach the test's view
of the page: assert on native UI instead (a menu label, a tab card's title).

Data lives in the app's `Application Support/Cra`: `tabs.json` (open and archived tabs),
`settings.json`, and `Snapshots/` with each tab's last picture.

## Matching Arc Search

Arc Search can't run on a Mac: the simulator has no App Store, App Store builds only run on
devices, and there is no Mac version. The reference is recorded footage, measured:

1. The App Store preview video is real footage from an iPhone 15 Pro, 886 × 1920 px at 30 fps,
   so **2.2545 px per point** (393 × 852 pt). `ffmpeg` extracts a frame; runs of colour along
   a row or column give edges to the pixel.
2. The same state is put up in an iPhone 15 Pro simulator (3 px per point), and the same band
   of both is stacked at one scale to compare.
3. The number goes into `Packages/CraCore/Sources/CraCore/Mobile` with a test that states it.

Motion is measured the same way: an edge is followed frame by frame (30 a second) and a spring
is fitted to how fast its distance to rest shrinks (`MobileMotion` has the fitted springs and
the test that states the rate).

That footage is from early 2024. Later builds changed some screens (the tab switcher's left
button became Spaces, the page menu grew rows); for those the reference is the screenshots and
videos listed in arc-search-reference.md, section F. iOS 26 draws a taller keyboard than the
footage's, so bands are compared from the sheet's top edge, not from the screen's.

AI features follow the Mac app's rule: only the device's own Apple Intelligence model, and
hidden where it isn't available. Arc Search's own AI features (Browse for Me, Pinch to
Summarize) used a cloud service that ends on 23 November 2026.

## TestFlight

TestFlight needs the paid Apple Developer Program, which Pane's team isn't in (14 Nov 2026).
`scripts/ios-testflight.sh` archives a Release build signed for team GWSB8L799B and uploads it
to App Store Connect; the build number is the commit count. It signs with the Apple ID in
Xcode ▸ Settings ▸ Accounts, or with an App Store Connect API key given as `ASC_KEY_PATH`,
`ASC_KEY_ID` and `ASC_ISSUER_ID` (the .p8 stays in `~/.appstoreconnect/private_keys`, never in
the repo). The app record for `uz.pane.ios` has to exist in App Store Connect before the
first upload. Builds are for iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`); `CRA_IOS_SIM="Pane iPad" scripts/ios.sh test …` runs the UI tests on an iPad simulator.

## Share extension

`iOS/CraShare` is "Pane" in other apps' share sheets. Done writes the link into the inbox, a
Keychain item (`MobileShareInbox.updateInKeychain`, service `uz.pane.ios.share-inbox`) in the access
group both targets claim, `$(AppIdentifierPrefix)uz.pane.ios.shared` (Info.plist's
`PaneKeychainGroup`): upstream's App Group isn't available to Pane's free team. The app takes the
links each time it becomes active (`SharedLinks.swift`). An unsigned Simulator build, which may not
use the group, keeps the item in its own. A test can put a link in the inbox as the extension would
with `-CraFakeShare <url>` (and `-CraFakeShareTo favorites`).

## Looking at the widgets

A UI test can open the simulator's widget gallery: `XCUIDevice.shared.press(.home)`, then on
`XCUIApplication(bundleIdentifier: "com.apple.springboard")` long-press an empty spot, tap Edit,
Add Widget, type "Pane" into the gallery's search field, tap the result and take screenshots
(swipe left for the medium one). Keep such a test out of the suite: it leaves the home screen in
edit mode.

A UI test that leaves SpringBoard in home-screen edit mode makes the next run fail with "Busy
(Application failed preflight checks)" for the test runner: `xcrun simctl shutdown` and `boot`
the simulator, then run again.
