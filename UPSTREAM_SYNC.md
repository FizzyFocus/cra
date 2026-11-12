# Upstream sync: VictorKildahl/cra → Pane

Pane is a fork of [Cra](https://github.com/VictorKildahl/cra) (remote `upstream`). It takes upstream's
work **commit by commit and never merges it**: `git merge upstream/main` would wipe Pane's own UI
(the sidebar, Library drawer, settings tab, themes) and its rebrand. This file is the record of what
became of every upstream commit, so nothing is ported twice or lost.

- **Decided through:** `b980028` (upstream/main on 11 Nov 2026). Every upstream commit up to it is under
  Ported or Skipped.
- **Triaged through:** `dc4ed11` (upstream/main on 12 Nov 2026). The 49 commits after `b980028` are under
  Pending, sorted into A, B and C, waiting for a decision.
- **Merge base:** `9927600`.

## How to sync

1. `git fetch upstream`, then `scripts/upstream-audit.py --new --conflicts`: the upstream commits this
   file doesn't account for yet, each with the files it would conflict in on main (a dry run with
   `git merge-tree`; nothing is written).
2. Triage them into Pending (A, B, C) below and move "Triaged through" to `upstream/main`.
3. Port what is picked, one category per pass, on a branch: `git cherry-pick -x <sha>` (the trailer is
   how the audit finds it), or a hand-port whose message says `hand-port of upstream <sha>` or
   `(after upstream <sha>)`. Conflicts are resolved hunk by hunk, never a whole file `--theirs`.
   `Tests/promises.lock`: take ours, then `scripts/promises.py --update`. Settings rows from upstream's
   SwiftUI panes go into `resources/web/settings/settings.js` and `SettingsBridge.editableKeys`;
   hunks in upstream's `Sharing.swift` (usage stats) stay out. User-facing text says Pane
   (`Brand.name`); symbols keep Cra's names (CLAUDE.md, "Brand").
4. Move each decided row to Ported or Skipped (with the reason) and move "Decided through".
   `scripts/upstream-audit.py` exits 0 when every upstream commit is accounted for.

## Ported

### Cherry-picked (53): `git cherry-pick -x`, the trailer names the upstream commit

| Upstream | Pane | What |
|---|---|---|
| `3d560c2` | `4002d09` | Settings ▸ Tabs: choose where the address bar goes, as in onboarding (#305) |
| `e1c8765` | `6ab64de` | Favorites: float music notes while a music site plays, as in Arc (#303) |
| `cab6d40` | `bf66a6b` | Command bar: Settings option to search only the current space's tabs (#307) |
| `d55e7a0` | `fab78a9` | Spaces: a search engine of their own, else the default (#306) |
| `e9dca23` | `4593344` | Easels: an Easel expanded from Peek shows the space's backdrop again (#309) |
| `31187f8` | `bda2f66` | Agents in Cra: a local MCP server for the agents you already run (#193) |
| `c247e40` | `aeda34e` | Picture in Picture reopens on the display it was left on; a space picked in a Little Window stays (#316) |
| `386fbf8` | `338b512` | Translate a page any time, as in Arc: the toolbar's translate button, the URL field's "Translation Available"  |
| `4e5ce86` | `a681fc9` | Little Window: a picked space stays in its window only, the next one follows the window used last (#316) |
| `0f20e1f` | `c792839` | Shortcuts: ⇧ and a digit records the digit, so ⌘⇧2 is saved as ⌘⇧2, not ⌘⇧@ (#321) |
| `6d6ede8` | `0243ad7` | Capture: ⌘⇧2 over a Peek captures the Peek's page, in the Peek (#320) |
| `cd8f3f5` | `0ddceb5` | Copy URL: ⇧⌘C with tabs picked in the sidebar copies every picked link, one per line (#322) |
| `b08beb3` | `b23b291` | Live folders: the built-in plugins stay built in when Cra runs from a path under /private |
| `cbb5753` | `c0f25bd` | Site controls: the Automatic Picture-In-Picture switch is per site, as in Arc (#326) |
| `13a283b` | `a7ecfdf` | App icon: set the picked icon again when Cra comes back to the Dock from the menu bar (#319) |
| `9ae7224` | `316bac8` | Picture in Picture: a window dragged past the screen's edge springs back into the nearest corner, as in Arc (# |
| `2bf4f8f` | `6171328` | Little Window: the "Open in" menu is Arc 1.172.1's, with 46 pt rows, a list that scrolls and no ⌄ with one spa |
| `72bfc8f` | `c40e9ae` | Little Window: menu commands act on the Little Window's page, not the browser window's tab (#333) |
| `bf2878d` | `e004027` | Little Window: Arc 1.172.1's gradient strip, grey traffic lights, and a host-only address pill with Arc's padl |
| `f7b1ba4` | `9c70174` | Engine: CEF 156.0.27 on Chromium 156.0.8078.96, Chrome's 9 Nov Extended Stable (#328, #323) |
| `3e3a82b` | `e9a788a` | Privacy: fingerprinting protection, a switch in Settings ▸ Privacy (CEF 156.0.27-codecs2) |
| `2b067f9` | `4219fbf` | Space dock: a right-click on a space's icon opens Arc's whole space menu (#339) |
| `f9319aa` | `6d49926` | Little Window: ⌥⌘N opens Arc's compact card, 490 × 329 pt at the top right with only the command bar (#337) |
| `f4ddb16` | `336b2c2` | Release: a release ships the newest CEF |
| `50adbd4` | `89a9715` | Screenshots: a screenshot app's window under the pointer over a page is the main window, not a blank one (#346 |
| `9ea5240` | `c04fa88` | 5-Second Previews: Arc Max's hover cards on the Mac's Apple Intelligence (#324) |
| `3d6548c` | `7bbcc9f` | Pinned tabs: a double-click on the favicon goes back to the pinned URL once and doesn't rename the tab (#345) |
| `241cc8c` | `7a95ae2` | Agents: one click adds Cra to Claude Code, Claude Cowork, Codex, Cursor, T3 Code or Conductor |
| `9d8749d` | `fbfdff9` | Release: the CRA_ALLOW_OLD_CEF repository variable lets the Release workflow ship the pinned CEF |
| `3a60bd3` | `06f3912` | Tabs on chrome:// pages open without their saved history: 0.1.38 crashed at launch on chrome://settings (#325) |
| `95f020f` | `c0900dd` | Scenario: a selected chrome://settings tab with a saved list survives a relaunch (#325) |
| `5887873` | `4287b94` | Page-top dragging: the page gets the press at once, text, links and resize corners keep their gesture, as in A |
| `7143532` | `0b03a03` | Page-top dragging: what the review of #335 read in Arc and saw with real drags |
| `d24295c` | `303896f` | View Source opens the page's source in a new tab, as in Arc (#348) |
| `5eca911` | `d68d9f8` | App icon: the picked icon stays in ⌘-Tab and the Dock after a download (#319) |
| `0fdf7df` | `7f4dc6a` | Page-top dragging: a drag on an inactive Cra moves the window every time, and never clicks the page (#335) |
| `52e8ef7` | `c8a6cdc` | Extension icons drawn from their 2x file, install prompts hang over Cra's window, no stuck post-install popup  |
| `9b6877e` | `4385d44` | Live folder plugins: the helper's sandbox is an explicit deny-all profile, so it runs when built with the macO |
| `ba49acf` | `940d4a5` | Sync: a later bundle from the other Mac is applied by itself, with no second question (#352) |
| `068df70` | `cd35b21` | Extension windows: one that opens over a full-screen Cra joins its Space instead of switching to a desktop (#3 |
| `5e02b46` | `ac25102` | Two displays: a new page no longer pulls the primary display off another app's full-screen Space (#354) |
| `60eb2c7` | `8634344` | DevTools in a Little Window and a Peek dock beside the page, as in the browser window (#348) |
| `afe4417` | `d20b2c9` | CEF update check: a later CEF on an older Chromium is not an update (#355) |
| `ad9fd40` | `e2c24c9` | View Page Source in the page's right-click menu opens the source, not the page (#348) |
| `e020f1d` | `083533f` | Picked tabs: Arc's menu for all of them, with Copy URLs and Share N Items (#356) |
| `1f88af4` | `58cae88` | Share Folder… on a sidebar folder copies a link anyone can open (#357) |
| `4d2961d` | `38eae92` | Page-top clicks: a press at the top of a page with the toolbar hidden is pinned to reach the page (#363) |
| `2a43142` | `6d5a046` | Blocked pop-ups: a button with Chrome's list, Open All and Always Allow; leaving a tab no longer lends it a us |
| `37efb05` | `4a71412` | Page-top dragging works as Arc's, measured side by side: 60 pt band, under the toolbar too, and a slipped clic |
| `d31a84f` | `4eff44c` | Picked tabs: Arc's current menu, Share N Items… copies a link (#356) |
| `deb7808` | `45be80a` | Blocked pop-ups: a tab the page opens itself leaves the button, and an address shows once (#357) |
| `109c697` | `44be647` | Picked tabs: Archive Items is Arc's menu for an Easel among the picks, not a pinned tab (#356) |
| `b980028` | `51ce1c3` | Share links: Arc's "Send this Folder to anyone" warning before Share Folder… and Share N Items… (#356, #357) |

### Hand-ported (4): Pane's own code after the upstream commit

| Upstream | Pane | What |
|---|---|---|
| `c1aadf7` | `6adf062` | Theme editor: − on the last colour goes back to the unthemed default (#300) |
| `b4c20de` | `f2f1840` | Settings: a line under each setting saying what it changes |
| `eda6089` | `77e2fa1` | Copy URL glyph: link → checkmark → link on a click (#361) |
| — | `f166b35` | Extensions popover and bookmark card follow the space's light or dark (upstream's idea, Pane's SpacePopoverTones; no single upstream commit) |

### Covered by Pane's own work (5): the behaviour is in, by another route

| Upstream | Why it isn't picked |
|---|---|
| `fb2c304` | Full screen with the sidebar hidden: Pane's WindowFill / fullscreen sidebar does it |
| `43e8adc` | ⌘S slides the sidebar, page and toolbar stay put (#317): Pane's docking motion |
| `b58b69d` | Library pushes the page past the window's edge (#340): Pane's Library drawer |
| `f5751d6` | ⌘W closes Settings (#364): Settings is a tab in Pane, so ⌘W already closes it |
| `537dc09` | Notes for #364 on SettingsWindowController, which Pane doesn't have |

## Skipped

For good unless the reason changes. "Never touch" areas are the owner's call (11 Nov 2026).

| Upstream | What | Why |
|---|---|---|
| `ff99afd` | Sharing: opt-in daily usage stats and crash reports | Telemetry: nothing leaves the Mac in Pane |
| `2eb5877` | Sharing: usage report 30 s after launch | Telemetry |
| `0495029` | Sharing: sidebar card asking to share usage stats | Telemetry |
| `c9bb58b` | Sharing docs for Phantom | Telemetry |
| `7be55ee` | Full screen: window can't be dragged, lights follow the transition (#308) | Collides with Pane's traffic-light fade and docking motion |
| `0473e3d` | Library: Arc's 417 pt sidebar (#302) | Library widths: never touch (Pane's drawer) |
| `22a8552` | Library gives way in narrow windows (#302) | Library widths: never touch |
| `50d2fa9` | Command bar: (i) badge opens the Site Control Center (#314) | Command bar: never touch (Pane's dropdown) |
| `0c81531` | Command bar: (i) opens the suggestions notice (#314) | Command bar: never touch |
| `dc404ff` | Space dock: hovered dot takes the wide cell (#252) | Dock dots: never touch |
| `e2ba4eb` | Floating sidebar inside the window's rounded corners (#341) | Floating-sidebar corner clip: never touch |
| `f2503d4` | Hidden sidebar: pointer thrown past the edge (#350) | Hidden-sidebar reveal: never touch |
| `7ad6b2f` | Hidden sidebar: reveal swings 4 pt (#350) | Hidden-sidebar reveal: never touch |
| `f46364a` | Hidden sidebar: window keeps its shadow (#350) | Hidden-sidebar reveal: never touch |
| `ba67d78` | Sidebar: edit the address in place (#344) | Pane keeps its URL dropdown |
| `9a62558` | Command bar ends an in-place address edit (#344) | Goes with `ba67d78` |
| `2a0ee52` | Switch to Light/Dark Mode turns the browser (#362) | Owner's call (B1) |
| `8f9af14` | Peek grows out of links in web components (#359) | Owner's call (B1) |
| `9d5160d` | Scenarios: no hang behind the reopen-windows alert; 1x snapshots | Upstream test infra; revisit if scenarios hang on that alert |
| `2e0134f` | Component snapshots re-recorded at 2x | Pane re-records its own snapshots after its UI pass |
| `dd2c4e4` | README: Easels and Boosts | Upstream's README |
| `7ee415b` | Install with Homebrew (victorkildahl/tap/cra) | Installs upstream Cra, not Pane |

## Pending

New on upstream since `b980028`, triaged on 12 Nov 2026 against main `028904a`. "Conflicts" is a dry
run of each commit alone onto main: *clean*, *lock/docs* (only `Tests/promises.lock` or docs, trivial),
or the code files. "Needs" is an earlier pending commit it builds on. "settings.js" means its
settings rows were written for upstream's SwiftUI panes, which Pane replaced with the
`pane://settings` page: they are hand-ported there.

### A: bug fixes, engine, tests (small, low risk)

| Upstream | What | Conflicts |
|---|---|---|
| `7665a0f` | Logi Options+ Back/Forward gestures navigate the page under the pointer, switch spaces over the sidebar (#369) | clean |
| `ebce13c` | Sync: a folder left with files from two writes is put right after a minute (#378) | clean |
| `ea617f9` | Sync: a file gone from the bundle is put right; a Mac not yet asked never writes over another's (#378) | SettingsSync, SettingsSyncService (Pane's sync folder change); needs `ebce13c` |
| `5a93a4c` | ⌃Tab: a tab opened in the background is next (#394) | clean |
| `ad76399` | Import: offer Chrome and Firefox from their data alone | clean |
| `dc4ed11` | MCP page_upload finds the file input behind an uploader's button, label or drop zone | clean |
| `5c6439a` | A space's emoji keeps its bottom row when macOS clips labels (#399) | lock/docs |
| `ac12d60` | Window managers: Moves moves the whole window, page and floating sidebar (#391) | lock/docs |
| `192b41e` | Window switchers: one page is one window (#401) | lock/docs |
| `747ad0a` | Music notes keep floating when muted and with Reduce Motion (#303) | lock/docs |
| `4d9beb0` | A muted tab stays quiet on its next page and after a relaunch (#387) | AppDelegate, CraCEF; needs `7cd69db` |
| `cba9995` | Scenario: ⇧⌘C with picked tabs copies their links (#322) | lock/docs |
| `915260b` | Scenario: Open in Split View splits picked tabs (#386) | lock/docs |
| `e9e4b7d` | Arc parity notes: Find and Replace is a skip | clean |

### B: new features

| Upstream | What | Conflicts |
|---|---|---|
| `72a30bf` | Sidebar rows and Favorites tiles push in while pressed (#367) | clean |
| `a866227` | Picture in Picture: a double click returns to the video's tab (#383) | clean |
| `f052e7c` | Picture in Picture: Arc's scrubber along the bottom (#384) | AppDelegate, PictureInPictureChrome |
| `546d50a` | Picture in Picture: resize up to the full display, rest on one display (#388) | PiP files; needs `a866227` |
| `c810a20` | Favorites: a Peek from a favorite badges the tile with its page's favicon (#381) | lock/docs |
| `7cd69db` | Favorites: Mute / Unmute row in a favorite's menu (#387) | AppDelegate |
| `1fd954f` | Mouse back/forward over the sidebar reach the Library before the first space (#233) | AppDelegate |
| `9629fd1` | Expand Current Split: the focused pane takes the window (220 pt minimum for the rest) | AppDelegate; shortcut row → ShortcutGroups |
| `61f209d` | Open in <space> ⌘O as Arc's Tabs row, only over a Little Window or Peek | AppDelegate; shortcut row → ShortcutGroups |
| `8ad3f9e` | Swipe back on a tab a link opened closes it to the tab it came from (#370) | MainWindowController |
| `43afe0e` | ⌘T in a Peek opens the window's New Tab bar; ⌘L still edits the Peek (#379) | MainWindowController |
| `9ce8012` | Permission requests in Arc's card at the page's top left, not a sheet (#371) | MainWindowController |
| `fccc893` | Peek buttons rise under the pointer and give under a press (#385) | LittleWindowController |
| `9dd665f` | Share N Items…: "N Items" title, "Copied Folder URL" toast (#356) | AppDialog; links are crabrowser.app's |
| `8d1f2b9` | Zap as in Arc 1.172.2: confirm popover, shelf of zapped elements | ShellView (Pane's docking/drawer code) |
| `761153e` | Boosts gallery: Share Boost… and Open in Cra from crabrowser.app/boosts | AppDelegate; depends on upstream's site, would need Pane wording |
| `e4b7447` | Easels: Arc's colours, picker, menus, undo, link cards, live captures (large) | AppDelegate |
| `e18f093` | Settings: Show full URL, More Settings…, Reset Translated-site Prompts; ⌥⌘-click opens a Little Window (#373) | settings.js; Sharing hunks out |
| `84accc5` | Follow-up to #373: ⌥⌘-click reads the click's keys; reset reaches every profile | needs `e18f093` |
| `c0981c0` | Peek: ⌘-click Expand loads in the tab the Peek came from, Links setting off by default (#380) | settings.js |
| `b478731` | Profiles: per-profile "New documents" app and a "New Google Doc"-style command (#375) | settings.js; settings.json format (fixture) |
| `fb6d039` | Previews: recent pages on Linear, Notion, Figma, Confluence (#376) | settings.js; SpaceColumnView |
| `b517a00` | Previews: Outlook Mail/Calendar and Notion Calendar (#376) | needs `fb6d039` |
| `115e806` | Shortcuts: per-shortcut Prefer Pane / Use Both / Prefer Websites (#374) | settings.js; keybindings.json format (fixture) |
| `2b39a45` | Ask on Page: find-or-ask card on ⌘F answered by Apple Intelligence, on device (#393) | settings.js (Max); MainWindowController |
| `dc6d118` | Ask on Page: the card as Arc drew it (#393) | needs `2b39a45` |
| `0b20792` | Spaces: a PNG or SVG as a space's icon (#395) | SidebarView, SpaceMenuIcon (not in Pane) |
| `167c05a` | Toolbar: "Hide the toolbar until you need it" (not in Arc, #405) | settings.js; ShellView, MainWindowController |

### C: collide with Pane's own UI

| Upstream | What | Why it collides |
|---|---|---|
| `80cdfe7` | Settings back in a native 684 × 650 window with ten tabs, member card, "Share Cra" (#372, #377) | Pane's Settings is the `pane://settings` tab; most of its 20 files are panes Pane deleted. Suggest skip |
| `caaa884` | Settings' first tab carries the user's first name (#372) | Needs `80cdfe7`. Suggest skip |
| `8f146f3` | Command bar: rows under a still pointer keep the top row selected (#382) | Command bar: never touch; its HoverGate logic could be hand-ported alone |
| `ffd7de6` | Themes: dark colours without the purple cast (#392) | Pane's theme pipeline (default tint, opacity, new-space tones); changes every dark space |
| `02d8f9a` | Themes: Dark keeps the picked colour (#392) | Needs `ffd7de6` |
| `904c9ca` | Themes: Light keeps the picked colour (#392) | Needs `02d8f9a` |
| `ed26238` | Peek: ⌘S toggles the window's sidebar, the Peek follows the slide (#402) | ShellView's docking and full-screen sidebar |

