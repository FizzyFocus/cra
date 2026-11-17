# Upstream sync: VictorKildahl/cra → Pane

Pane is a fork of [Cra](https://github.com/VictorKildahl/cra) (remote `upstream`). It takes upstream's
work **commit by commit and never merges it**: `git merge upstream/main` would wipe Pane's own UI
(the sidebar, Library drawer, settings tab, themes) and its rebrand. This file is the record of what
became of every upstream commit, so nothing is ported twice or lost.

- **Decided through:** `f8a6402` (upstream/main on 16 Nov 2026). Every upstream commit up to it is under
  Ported or Skipped.
- **Triaged through:** `f8a6402`. Nothing is Pending.
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

### Cherry-picked (300): `git cherry-pick -x`, the trailer names the upstream commit

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
| `e9e4b7d` | `c16f8a6` | Arc parity: Find and Replace is skip (does nothing in Arc 1.172's Easels or pages) |
| `cba9995` | `db4a384` | Copy URL: a scenario types ⇧⌘C with tabs ⌘/⇧-clicked and reads the clipboard (#322) |
| `747ad0a` | `98f4fc6` | Music notes: muted and Reduce Motion keep them floating, as in Arc 1.172.2; parity row done (#303) |
| `7665a0f` | `481109f` | Logi Options+'s Back and Forward gestures navigate the page under the pointer, and switch spaces over the side |
| `ebce13c` | `98f6ee8` | Sync: a folder left with files from two writes is put right after a minute, not waited on for ever (#378) |
| `ea617f9` | `3503754` | Sync: a file gone from the bundle is put right too, and a Mac not yet asked never writes over another Mac's bu |
| `ad76399` | `12b45cc` | Import: offer Chrome and Firefox from their data alone, as Arc, Dia and Zen are |
| `7cd69db` | `022ad01` | Favorites: Arc's Mute / Unmute row in a favorite's menu, after Rename… (#387) |
| `5c6439a` | `c4937c8` | Sidebar: a space's emoji keeps its bottom row when macOS clips labels to their frame (#399) |
| `915260b` | `81f385f` | Picked tabs: test that Open in Split View splits the picks, and note that Arc's ⌃⇧= ignores them (#386) |
| `ac12d60` | `29707cc` | Window managers: Cra's page and floating sidebar are part of its window, so Moves moves the whole window (#391 |
| `5a93a4c` | `18110bb` | Tab switcher: a tab opened in the background is next on ⌃Tab, as in Arc (#394) |
| `4d9beb0` | `217cc65` | Mute: a muted tab stays quiet on its next page and after a relaunch (#387) |
| `192b41e` | `0b5436e` | Window switchers: one page is one Cra window, locked for #401 |
| `dc4ed11` | `7d6e45c` | MCP: page_upload finds the file input behind an uploader's button, label or drop zone, in open shadow roots an |
| `9629fd1` | `3f84e5e` | Expand Current Split: the focused pane takes the window and the others keep Arc's 220 pt minimum |
| `61f209d` | `f2a5f67` | Open in <space> ⌘O is Arc's Tabs row: after Pin Tab, only while a Little Window or Peek is in front |
| `72a30bf` | `4d55115` | Sidebar rows and Favorites tiles push in while pressed, as in Arc 1.172 (#367) |
| `8ad3f9e` | `e9a754b` | Swipe back: a two-finger swipe on a tab a link opened closes it to the tab it came from, as Back does and as i |
| `e18f093` | `bbc3388` | Settings: Show full URL, More Settings… and Reset Translated-site Prompts, and ⌥⌘-click opens a Little Window  |
| `84accc5` | `c318626` | Settings: ⌥⌘-click reads the click's own keys, and Reset Translated-site Prompts reaches every profile and Arc |
| `43afe0e` | `360ee42` | ⌘T in a Peek opens the browser window's New Tab bar with its tabs; ⌘L still edits the Peek (#379) |
| `9ce8012` | `1808e61` | Permission requests ask in Arc's card over the page's top left corner, not a sheet over the whole window (#371 |
| `c0981c0` | `4f508e8` | Peek: ⌘-click Expand loads the page in the tab the Peek came from, behind a Links setting off by default (#380 |
| `c810a20` | `b25c807` | Favorites: a Peek from a favorite puts its page's favicon on the tile's top right corner, as Arc 1.172.2 does  |
| `a866227` | `d5e0dc0` | Picture in Picture: a double click on the video returns to its tab (#383) |
| `f052e7c` | `7e162fd` | Picture in Picture: Arc's scrubber along the bottom of the window (#384) |
| `fccc893` | `e6643af` | Peek buttons rise under the pointer and give under a press, as Arc 1.172.2's do; ⌘W and ⌘O press theirs (#385) |
| `fb6d039` | `ae7493e` | Previews: recent pages on Linear, Notion, Figma and Confluence, on favorites and pinned tabs, with Arc's check |
| `115e806` | `dce0233` | Shortcuts: Arc's choice per shortcut of who gets the keys, Prefer Cra, Use Both or Prefer Websites (#374) |
| `b517a00` | `09a31bd` | Previews: Outlook Mail, Outlook Calendar and Notion Calendar, read with the page's own sign-in, completing Arc |
| `2b39a45` | `8668f71` | Ask on Page: Arc Max's find-or-ask card on ⌘F, answered by the Mac's Apple Intelligence (#393) |
| `546d50a` | `d1aa626` | Picture in Picture: resize up to the full display, and always rest on one display (#388) |
| `dc6d118` | `0189ce5` | Ask on Page: the card as Arc drew it, from the reporter's capture (#393) |
| `4b0ba66` | `082072f1` | Hidden tabs: five keep their last frame instead of ten, 75 MB less GPU memory at 20 tabs (#195) |
| `21bee29` | `66a9e019` | Background test copies: windows on screen report themselves visible, so their pages keep drawing |
| `0b0b328` | `0a7f4948` | Window managers: a nil child window no longer crashes Cra (#391) |
| `f6a8736` | `e6a76afc` | Space switches: the list doesn't ask the window server which window is under the pointer every frame |
| `3726f65` | `c79d4e8c` | Engine: Google services Cra never offers are off (optimization hints, AI history search, Gemini, Lens) |
| `b8de1e5` | `3674b710` | Speed: the framework is linked at launch, so each page process is ~14 MB smaller |
| `8429b73` | `7ad32bab` | Ask on Page: the question reads on a dark card, also in a light space (#408) |
| `ff83e6e` | `fc766b9e` | Speed: hidden tabs' frames go 2 s after a switch, a few windows at a time |
| `f586c7f` | `6558dcee` | Today: Clear keeps the tab on screen and tabs playing sound, as in Arc (#406) |
| `305439a` | `23a1a2d0` | Incognito: the space header's menu offers no Set Profile, Export or other space-only rows (#413) |
| `272980a` | `5207ce48` | Import: Arc spaces with an Icon-tab glyph keep it, not 🗂️ |
| `805a3b7` | `78ceffd8` | Ask on Page: a follow-up gets its own answer, not the last one again (#417) |
| `30afd28` | `6a8da774` | Password managers: extensions see the page Cra has focused as the active tab (#414) |
| `c9e0134` | `c791dbf9` | App Shortcuts: a ⌃, ⌥ or F-key App Shortcut works while a page has the keyboard (#253) |
| `fca4564` | `71f3331f` | Sidebar: a space's emoji draws itself, so macOS 27 doesn't cut its bottom off (#399) |
| `990cae0` | `1eac4345` | Ask on Page: quotes come from the page, follow-ups quote it, long answers stream smoothly (#417) |
| `9cc14d3` | `3dd76e76` | Ask on Page: an answer that copies the page back is never shown; Cra asks again |

The 12 Nov 2026 sync (34 picks, branch `upstream-sync-nov12`) adapted these to Pane; each commit's "Fork port:"
paragraph has the detail:

- Settings rows from upstream's SwiftUI panes are in `pane://settings` and `SettingsBridge.editableKeys`: Tabs &
  Spaces ▸ Little Windows & Peek (⌥⌘-click opens a Little Window, ⌘-click Expand opens in the tab), a Previews
  card with Arc's seven (Folders and Gmail moved into it, Google Calendar got a row), Advanced ▸ Chromium (More
  Settings…, Reset Translated-site Prompts), Max ▸ Ask on Page, and a priority pop-up per shortcut in Shortcuts
  (Prefer Pane / Use Both / Prefer Websites; "Edit the shortcut" opens `pane://settings/shortcuts?action=<id>`).
  "Show full URL when Toolbar is enabled" was not added: Appearance's Show full URLs is the same setting.
- The permission card keeps Arc's layout in Pane's popover look (SpacePopoverTones, frosted material).
- Preview cards' new lines use CardStyle.text (light or dark with the sidebar), not upstream's white.
- The Tabs menu keeps Pane's Bookmark This Page… row before New Folder…; `expandSplitPane` is under Split View.
- `Sharing.swift` (usage stats) hunks stayed out; AskOnPageTests checks the settings page instead of UsageStats.
- ShortcutPriority's titles and lines say `Brand.name` (Prefer Pane); #374's locked test expects Pane's words.
- `9c566c9` (Pane's own, after `ebce13c`): the sync's newer-version error names Pane.
| `39aa7bb` | `cc2871fa` | Tab freezing: a page holding a WebSocket is never frozen; tabs past the five used last freeze; closed tabs' memory goes back |
| `935cca1` | `4757e658` | New tabs: a page made ahead takes the click's 34 ms of window-making off it (spare pages) |
| `14b921f` | `76b88091` | Player: a notification ding or Web Audio alone makes no sidebar card, as in Arc (#411) |
| `4ad54a1` | `bfc5f082` | Sidebar: a tab switches on the press, as Arc's does, not on the release |
| `426c345` | `fc0356b6` | Instant Links: Arc Max's Shift-Return opens the top results, planned by the Mac's Apple Intelligence (#409) |
| `115a201` | `3ae52cd4` | Sidebar: a link dragged in from a page or another app opens as a tab where it is let go, as in Arc (#419) |
| `308817d` | `79a1b493` | Sidebar: a link let go on a tab's middle opens nothing, as in Arc (#419) |
| `c61aab7` | `9a90bb28` | Back and Forward: right-click lists the tab's history, as in Arc (#416) |
| `3831d67` | `c09fe784` | Air Traffic Control: a URL typed in ⌘T follows a route to a space, as in Arc (#421) |
| `4e0c10b` | `7547f008` | Sidebar: a link let go on a folder's middle goes in the folder, at the top, as in Arc (#419) |
| `a4192fe` | `619ba9f2` | Sidebar: the insertion line is Arc's ring and line, from #422 (#419) |
| `60cf686` | `ea702821` | Split view: drag a sidebar tab or a page's link onto the page to split it, as in Arc (#419) |
| `20de2af` | `c68b8b97` | Instant Links: a Google /goto result opens its own page, not Google's "verifying your request" first |
| `2908a25` | `d360d670` | Split view: a tab dragged on to the page's far edge splits on that side, not the region it opened in the middle (#419) |
| `5aa1df1` | `0fc5f147` | iPhone app, first pieces: search sheet, bottom bar and tabs to Arc Search's measurements |
| `1d15a9a` | `c07930b9` | iPhone app: tab switcher, page menu, Site and App Settings, Archive, with UI tests |
| `38239b7` | `93ac1034` | iPhone app: ads, trackers and cookie banners are blocked, per site, and counted |
| `72f95e7` | `f081fbec` | iPhone app: Arc Search's swipes |
| `b9d19d9` | `429a030b` | iPhone app: Reader, and Summarize by tile or pinch on the device's own model |
| `082be90` | `19824100` | iPhone app: Browse for Me, made on the phone |
| `076a66e` | `338e63b9` | iPhone app: incognito looks and behaves as Arc Search's |
| `5d185ef` | `ee299160` | iPhone app: the Mac's Spaces, and favorites under the search field |
| `65f6e16` | `6097bfe8` | iPhone app: the tab row moves at Arc Search's speed, and a drag up from the bar opens it |
| `85a0d46` | `36d6a861` | iPhone app: voice search by holding the pill |
| `ae423f9` | `a6f5f0ef` | iPhone app: onboarding, the four app icons, quick actions and App Shortcuts |
| `7112b72` | `4bac812f` | iPhone app: downloads, page dialogs, widgets, the empty home screen; where the work stopped |
| `b06bd87` | `a1d09452` | iPhone app: pages the phone knows come up as you type, long suggestions take two lines |
| `9580594` | `478ad14d` | iPhone app: signed for the team, iPhone only, and a script that uploads to TestFlight |
| `9c30c32` | `a54f9bb5` | iPhone app: the TestFlight script's messages no longer break bash 3.2 on "…" |
| `8d6f453` | `ddc06c39` | iPhone app: the iCloud container the Mac syncs into, so a real phone sees the Mac's Spaces |
| `3e476b6` | `da7f03b2` | iPhone app: the floating switch between Browse for Me and the search engine |
| `6dfe980` | `685112ce` | iPhone app: Browse for Me can be the search engine, as in Arc Search's engine menu |
| `c811283` | `8d469c0b` | iPhone app: "Browse for Me" in a page's edit menu for selected text (Arc Search 1.23) |
| `6aed87e` | `66fbd180` | iPhone app: a Browse for Me action for Shortcuts and Siri |
| `3519090` | `c0851554` | iPhone app: the share extension and its "Saved" screen, as in Arc Search |
| `01bfc2a` | `460075b1` | iPhone app: Translate in the page menu, on the phone with Apple's Translation framework |
| `5444cc6` | `2f0fd52b` | iPhone app: scroll through the suggestions and each one comes up into the field |
| `1810f12` | `4a117b7e` | docs: plain quotes in the scroll-through row |
| `b922ba9` | `a1e766ab` | iPhone app: the search sheet in Arc Search's 2025 colours |
| `b49529c` | `dec71cb8` | iPhone app: "Open App Links in..." takes effect: tapped links to another site go to its app |
| `25bfa16` | `59d2d597` | iPhone app: the widgets in Arc Search's look, checked in the widget gallery |
| `c048088` | `041ff0ff` | iPhone app: "Bring Cra to your home screen", Arc Search's widget walkthrough |
| `2905119` | `c1415fd6` | iPhone app: Change App Icon opens Arc Search's dock sheet; App Settings in its later order |
| `7022194` | `52706b93` | iPhone app: Languages: what Browse for Me, summaries and Translate answer in |
| `8222f9f` | `8d11c9ca` | iPhone app: custom search engines: an https address with %s for the query |
| `cdbda1f` | `5714329d` | iPhone app: the dark search sheet as in Arc Search's dark-mode clip, glow included |
| `43aa228` | `87aa047f` | iPhone app: onboarding's "Pinch to summarize any web page" step, acted out on a loop |
| `0101d0d` | `f959b520` | iPhone app: the mic in the search field starts voice search (Arc Search 1.19) |
| `c7a0e8a` | `8e53df5b` | iPhone app: the default-browser step in Arc Search's words: three steps, Open Settings, Not now |
| `05ea070` | `781e874d` | iPhone app: Copy and Share on a finished summary |
| `a19acc6` | `2535c9a2` | docs: Pin to Space as a proposal (phone-pins.json beside the sync bundle), waiting for a decision |
| `8f02fc9` | `334522a9` | iPhone app: Summarize folds the page as Arc Search does |
| `4f1bd72` | `59d02962` | docs: the whole iPhone UI suite passes (50 tests), and what to do when the simulator keeps dying |
| `c89f1e5` | `a5184797` | docs: the iPhone UI suite has 41 tests, not 50 |
| `16bcba5` | `2197e022` | iPhone app: Browse for Me pages end with follow-up questions and their Sources (Arc Search 1.24) |
| `fff5a49` | `a49ce785` | iPhone app: landscape keeps the search field and the page menu on screen |
| `7759f2d` | `94fcbab5` | iPhone app: the Spaces sheet has white text on a dark Space, as Arc Search's does |
| `0a152f5` | `20759e45` | iPhone app: iPad too, as Arc Search runs there; the page menu keeps a phone-like width on iPad |
| `0bfcabf` | `97189c01` | iPhone app: favorites under the search field can be dragged into a new order |
| `2479f20` | `4deb6c96` | iPhone app: the question at the top of a Browse for Me page opens it for editing |
| `128488b` | `cb8960aa` | iPhone app: starter questions under the empty field until the first search (Arc Search 1.13) |
| `cebc99a` | `a2955a3b` | iPhone app: Dynamic Type for Browse for Me pages, the search field and rows, and Settings |
| `8fb1a31` | `e9575f76` | iPhone app: onboarding's text follows Dynamic Type too |
| `a06b9e6` | `c85d254a` | iPhone app: a Browse for Me page slides up as its loading screen fades |
| `e632a79` | `2975ca68` | iPhone app: fix the rejected TestFlight builds; the upload script now waits for Apple's verdict |
| `be2bfbf` | `2282b5db` | iPhone app: ask iCloud for the Mac's sidebar instead of waiting for it to turn up |
| `6a519e7` | `512c9616` | docs: index of Victor's Arc Search recording (13 Nov), screen by screen |
| `0ed640a` | `f9fa4242` | iPhone app: the page menu in Arc Search 1.49's design, from Victor's recording |
| `4709bbe` | `c560f329` | iPhone app: the page menu on dark glass like Arc Search 1.49, tile labels at 13 pt |
| `ecd8525` | `56457227` | iPhone app: Arc Search's blocker tip and "Did it fix the issue?", from Victor's recording |
| `fc418af` | `28fbef9b` | iPhone app: Site, App and Default Site Settings and the Archive as in Arc Search 1.49 |
| `7248d08` | `d1da0a50` | iPhone app: Arc Search 1.49's coach mark and starter questions, from Victor's recording |
| `1018939` | `4f056148` | iPhone app: the page menu and settings follow the phone's appearance |
| `7de8131` | `e04280d1` | iPhone app: onboarding rebuilt as Arc Search 1.49, from Victor's recording |
| `cf1593a` | `b4a78103` | iPhone app: plain pages are white in dark mode; Summarize on Arc Search's dark gradient |
| `8605121` | `7223a90b` | iPhone app: Cra's "Sync with Cra for Mac" sheets and the tab row's sync card, after Arc Search 1.49 |
| `b3cff22` | `5ba4a08c` | docs: Browse for Me feedback thumbs left out of the iPhone app (nowhere to send them) |
| `b199834` | `874c23c7` | iPhone app: Browse for Me and Summarize show on every iPhone that can run Apple Intelligence |
| `56be95d` | `4353dd9e` | iPhone app: the Mac's synced Spaces show up; the phone reads the Mac's dates |
| `89982b1` | `07599cbc` | Snapshot: the space dock's open emoji whole and centred (solid-spaces) |
| `5bb7467` | `d17b6169` | Engine: plan to leave CEF for Chrome's own framework, and the test build's layer and checks |
| `21a273c` | `ef6522f0` | Engine: the test build passes (12 checks), 20 tabs 706 MB with a 102 MB browser process; Aperitif helpers nee… |
| `555d14e` | `b03b9a3a` | Engine: build-chromium.sh for a Chrome stable tree; the layer turns on Aperitif helpers; stand-in Widevine si… |
| `b6d131b` | `d8c82555` | Engine: how start-up maps from CEF to ChromeMain |
| `84b2a83` | `28834749` | Engine: Chrome 157.0.8103.81 tree checked out; layer deps for 157, background mode stays in the build |
| `03bc8d0` | `3a2ccfb3` | Chromium engine: Chrome 157 builds with Cra's layer, the test passes all 12 checks |
| `144befb` | `b7982d73` | Chromium engine: Cra's app runs on Chrome's framework |
| `e23b0c8` | `934cbb8b` | Chromium engine: page protocol session, Cra's patches, prefs, extension windows |
| `40fb377` | `15a6fb4f` | Chromium engine: the sidebar player's media-session follow-up from #411 waits on the bridge |
| `708ef2a` | `dcb0ffd6` | Chromium engine: watch Chrome's new windows through ScopedObservation |
| `ab02876` | `f0630797` | Chromium engine: keys in Cra's pages go to Cra, never to Chrome's shortcuts |
| `c33d3eb` | `002ffe4b` | Chromium engine: favicons, theme and background colours, find, zoom, SSL status |
| `78f0456` | `facc609a` | Chromium engine: downloads go where Cra says, with progress and controls |
| `966d2be` | `3683a034` | Chromium engine: permission requests go to Cra's own prompt |
| `52b0b11` | `a0cf6f4e` | Chromium engine: element fullscreen and the link status line are Cra's |
| `b2ad0c2` | `9afc8b6b` | Chromium engine: restored history, spare pages and side panel pages |
| `69ba79a` | `079de3b0` | Chromium engine: DevTools open in Cra's card |
| `49658e9` | `36681e7b` | Chromium engine: closing a tab is a forced close, as CEF's |
| `8b245b4` | `c97a4124` | Chromium engine: Picture in Picture and print |
| `76fcf03` | `b436f881` | Chromium engine: a tab opened for a download stays Cra's |
| `22e2beb` | `82747556` | Chromium engine: Cra's document start scripts in every page |
| `cbbc46f` | `babe7a45` | Chromium engine: Cra's ad and tracker blocking |
| `34e6042` | `6ac0c86a` | Chromium engine: blocked pop-ups list and the site's pop-up setting |
| `a1bdf2d` | `89357e01` | Chromium engine: capture indicator, process events, incognito end |
| `a919d1a` | `55046fd3` | Chromium engine: browser fetches with a profile's cookies |
| `727af23` | `d01c3f6c` | Chromium engine: a page's pop-up is offered with the address it opens |
| `8280b11` | `ee95ba9b` | Chromium engine: Arc's page menu |
| `d91f8a8` | `77be48b9` | Chromium engine: Picture in Picture over full-screen Spaces, stray windows stay put |
| `d4bb5d3` | `c6a1a6a0` | Chromium engine: a second launch hands its URLs to Cra |
| `85e6639` | `7a787d2f` | Chromium engine: status, 13 Nov evening |
| `a08d88c` | `d1a86fff` | Chromium engine: Cra.mediaSession through Chrome's public media session |
| `df16801` | `820c8037` | Chromium engine: Chrome's bubbles find Cra's window (extension popups) |
| `10e28a2` | `74688475` | Chromium engine: agent pages render unseen, agent downloads |
| `de3af69` | `6c89e328` | Chromium engine: keep Chrome's hidden windows from key by swapping the method |
| `52e297c` | `af808613` | Chromium engine: Cra.installFromWebStore |
| `94a1897` | `b4f452d0` | Chromium engine: runChromeCommand (Task Manager, Cast) |
| `7778324` | `512a7a48` | Chromium engine: pop-up addresses from the opener, observers gone at quit |
| `b17ab3f` | `9d5ee363` | Chromium engine: no page is started while quitting |
| `b08c01e` | `21854c4d` | Chromium engine: unregister from the profile manager by the pointer we have |
| `f38f787` | `70d50260` | Chromium engine: downloads with no page of Cra's go with the profile's last page |
| `5442f95` | `b9cc30e6` | Chromium engine: Google's background services off, fingerprinting protection in |
| `8a331cb` | `140bac17` | Chromium engine: leave out ungoogled's disable-crash-reporter |
| `f4287f0` | `e81c4fa7` | Chromium engine: build.sh takes the engine output of the CPU it builds for |
| `e402f77` | `dfdbd2c5` | cra://open closes the command bar that waited for a new tab |
| `8dfa38a` | `82672560` | Chromium engine: Cra's branding, published engine, Chromium the default |
| `11cc814` | `2293b535` | Chromium engine: CI and releases fetch the engine and check it is Chrome stable |
| `6979aa5` | `a33acb5b` | Docs: the engine in CLAUDE.md's layers and development.md's build |
| `0a13281` | `426c5226` | Releases: the newest engine, the hook checks it, release.md says how |
| `1441866` | `36c38c4d` | Tests: the store and fuzz harnesses compile EngineFramework with SafeStorage |
| `c162531` | `3d47c6b4` | Chromium engine: build Chrome 158.0.8127.37, the Mac stable |
| `44cce5e` | `9528db33` | Player: on Chrome's framework the sidebar card follows the page's media session (#411) |
| `befe6ad` | `65e1fc4a` | build-chromium.sh: a version bump fetches only the new tag, one commit deep |
| `5ee9254` | `2a9a0132` | Chromium engine: Cra's patches rebased onto Chrome 158.0.8127.37 |
| `ca60c59` | `f6c48e65` | Chromium engine: Document Picture in Picture is TYPE_FLOATING in Chrome 158 |
| `9f57c00` | `f401d89d` | Engine migration test: a Cra on CEF's data folder opens on the engine |
| `a0c2a0e` | `7c1cf016` | Chromium engine: links Cra opens its own way, sound as it happens, Picture in Picture time |
| `6f29b6d` | `973a54f0` | Chromium engine: Peek grows from the link, WebKit tabs get player cards, Chrome's quit watchdog kept |
| `94a09e9` | `8b2f8a66` | docs: the engine's quit, host windows and debugger bar, as found on 14 Nov |
| `dc2731e` | `deb33180` | Chromium engine: 5-Second Previews, page focus and the find bar find the page in its card |
| `3dee573` | `45b11b2b` | Chromium engine: fetch-engine.sh pins engine-158.0.8127.37-1; Little Windows measure the page in their card |
| `8c05f38` | `6895084e` | Chromium engine: Chrome's bars, pages' pop-ups as tabs, side panels, Little Window DevTools |
| `3f11358` | `25f6a0dc` | Chromium engine: DevTools report the panel they show |
| `bece1bd` | `5a6750fa` | docs: the engine's slow quit no longer happens (plain Chrome quits in 0.1 s) |
| `ababf5a` | `599e2fd2` | Chromium engine: a muted tab stays muted when its page navigates |
| `556d64a` | `fea1b9fb` | Chromium engine: a tab's restored history is reported once the app knows the tab |
| `86f5d71` | `029489c5` | docs: the hand checks before the engine ships |
| `9b3dff7` | `b6e206f8` | fetch-engine.sh: engine-158.0.8127.37-2, with the 14 Nov bridge fixes (arm64 and x64) |
| `e86910d` | `9f5879fa` | Chromium engine: actions reach a Peek or Little Window with no Chrome window per page |
| `55a75dc` | `18b273b1` | Chromium engine: a tab behind asks for permission when its tab shows, as Cra decides |
| `f343676` | `d48dbe55` | Chromium engine: spare pages, no quit crash, extensions don't see the placeholder, switchers skip Chrome's wi… |
| `7b702b1` | `600cc243` | Chromium engine: page windows on the Cra window in use (#354), spares a tab can take; emoji in snapshots |
| `1a9a408` | `42be2d22` | fetch-engine.sh: engine-158.0.8127.37-3 (arm64 and x64), with every 14 Nov bridge fix |
| `0f4ef1b` | `3945d23e` | Chromium engine: session cookies outlast a restart, Safe Browsing gets its key, versions without CEF |
| `91c011b` | `3e13e062` | fetch-engine.sh: engine-158.0.8127.37-4 (arm64 and x64): session cookies, Safe Browsing key |
| `3ec7f55` | `4923d81d` | Chromium engine: an extension's window over a full-screen Cra joins its Space; toolbar snapshot re-recorded |
| `b97c1b5` | `de9c2c3b` | Engine: the cookies and passwords Cra on CEF saved still decrypt |
| `300b113` | `335f4861` | fetch-engine.sh: engine-158.0.8127.37-6 (arm64 and x64): CEF's cookies and passwords decrypt |
| `61bb806` | `6d92f95e` | Engine doc: every scenario passes on engine -6 |
| `e9a89e5` | `7fe8fac1` | Engine doc: Sparkle from a CEF build to the engine build works |
| `62a0e99` | `c3206d52` | Engine doc: passkeys are offered with the release profile; the Web Store offers Add to Chrome |
| `ae2a545` | `acd6d672` | Engine doc: the x64 build under Rosetta passes every scenario that runs without a screen |
| `6fc2fec` | `4fcc14ac` | engine-migration.sh: not a harness, so CI's coverage run no longer picks it up |
| `06e7cab` | `d2d37479` | Engine doc: merged into main, not yet released |
| `3806ce0` | `7cc740f9` | Engine doc: the x64 build passes every scenario under Rosetta |
| `7ff42c7` | `8a8de7a3` | Engine doc: point at the right speed numbers |
| `aa290c4` | `7559ad14` | Engine: feature lists on the command line join Cra's |
| `40b006e` | `fd854e98` | Engine: Chrome's hidden windows stop drawing |
| `580f2db` | `5d26ba47` | Engine: a hidden page keeps its compositor |
| `de64db6` | `d6e4489d` | Scenarios: the popup check in a scenario of its own |
| `bbf70c2` | `ea505fd0` | Engine -7: idle wakeups and tab switch as on CEF |
| `9503920` | `c0a2df9d` | Engine: downloads from the profile's history aren't new downloads |
| `c186455` | `7d7b600c` | Engine -8: downloads from history stay quiet |
| `6525669` | `1f2da4a5` | Engine doc: 1Password trusts Cra only in /Applications |
| `971daa5` | `479bf79f` | Engine doc: Victor's day on his profile copy, passkey check skipped |
| `3f34d02` | `90e3bae6` | Engine doc: no real Intel Mac before the release (Victor's call) |
| `11a2a55` | `fb6527ff` | Engine: the hidden window's blank page has no renderer |
| `7fc0341` | `4c780617` | Engine -9: the hidden window's blank page has no renderer |
| `319d0a0` | `cfb7dfaf` | The daily update check follows Chrome stable; docs say the engine, not CEF |
| `5fc2322` | `066fe43c` | build.sh: the other CPU gets its own engine folder, not CEF's |
| `12d5dab` | `f9752e6c` | Engine -10: a live folder's plug-in gets non-2xx answers with their status |
| `79ddc8e` | `f9c2a668` | build.sh: sign the engine's libraries, and check every binary for notarization |
| `3a11ffc` | `b71e2fe3` | Notifications show Cra's icon, not Chromium's |
| `a4e67c2` | `c6109ff2` | Engine -11: the blocker stops ad frames again |
| `2f5e3b0` | `4d10b3e1` | A Cra owns its data folder when no other process holds it, not when no other Cra runs (#299) |
| `0ea8123` | `d09799af` | Theme grain: a pattern Core Animation tiles, not a drawn view |
| `f27aa5c` | `b55a668c` | Theme grain: the texture is 2x whatever screen is main |
| `11e4dec` | `406ff0d2` | Remove unused iOS store callbacks (#439) |
| `a3c6789` | `d6bdeb82` | TabStore: one blank line where #439 removed onChange |
| `1b0634c` | `208deef5` | Tidy Downloads: Arc's prompt, suffix and clash rules (#441) |
| `f11c0eb` | `bc8b0bc3` | Blocker: a blocked request fails instead of being cancelled, so pages that wait on it show (#436) |
| `64b20c0` | `6b3d1b67` | Import: offer a browser macOS keeps from Cra, asking for Full Disk Access |
| `8cc7ac7` | `43828b3e` | Find bar goes with its tab, as in Arc (#454) |
| `2507db1` | `215e9740` | Fix preview image size, search escaping and iOS popups (#447) |
| `39615a1` | `bd9a0c5e` | iOS popups: a closed opener's page is let go; ios.sh test starts the popup fixtures (#447) |
| `dc7e3ef` | `09e2b333` | Ask on Page: typed answers, whole quotes checked on the page, Return asks after Find finds nothing (#440) |
| `234639e` | `6aa770bb` | 5-Second Previews: Arc's optional summary and search focus, checked redirects (#442) |

The 13 Nov 2026 sync (17 picks, branch `upstream-sync-nov13`: the triage's bug fixes and engine/memory
work, no CEF update) adapted these:

- Today ▸ Clear (`f586c7f`): Pane's sections are headings, not one row: Clear takes their tabs and splits one
  by one, so the tab on screen keeps only itself in its section (upstream kept a whole tab group).
  `StoreTests.clearTodayClearsInsideSections` pins it, ⌘Z included. The Clear button stays `undoable`.
- Framework linked at launch (`b8de1e5`): `build.sh` checks `Pane Helper.app`; Pane's Apple Development signing
  is untouched. Its `CRA_PREWARM` early return in the helper stays out with upstream's update warm-up.
- Hidden frames (`4b0ba66`): `ScalableFrameEviction` is off without `AutofillAiWalletPrivatePasses`, which
  comes with `39aa7bb` (Pending, CEF codecs5).
- Password managers (`30afd28`): `Tests/Fixtures/TabsQueryExtension` comes in with it (upstream made it in
  `935cca1`, Pending); the scenarios install it by path.
- Incognito space menu (`305439a`): `SpaceMenu` keeps Pane's `asked` point; the profile pill already hid there.
- `docs/speed.md`, `scripts/perf` and the #407 Instant Links checklist lines stayed out wherever these touched them.

The CEF pass the same night (3 picks, branch `upstream-cef-codecs7`) took Pane from `cef-156.0.27-codecs4` to
`codecs7` in one step:

- The codecs7 framework gets Pane's Keychain item: `scripts/cef-keychain-item.py` rewrote 2 + 2 places (the
  service copy to 17 bytes, the account to "Pane") in the same instruction shapes as codecs4, checked by a byte
  diff and disassembly against the untouched download, and at runtime: under lldb, the framework's own
  `SecItemCopyMatching` asks for service "Pane Safe Storage", account "Pane" (Chromium 156 no longer calls
  `SecKeychainFindGenericPassword`).
- Spare pages (`935cca1`): a tab takes a spare only when `PageEngines.nativeOwns` doesn't own its address (Pane's
  hook: `pane://settings` and easels; upstream's `isNativePage` knew only easels, so a Settings tab would have
  loaded in a Chromium spare). Settings ▸ Profiles ▸ Delete drops that profile's spare. New scenario
  `spare-page-boost-extension`: a tab that took a spare is boosted from its first document and an extension's
  content script sees it as the active tab.
- `AutofillAiWalletPrivatePasses` is off now (`39aa7bb`); `scenario.sh` has the WebSocket server beside Pane's
  icon-site server; `-ApplePersistenceIgnoreState` stays out with `9d5160d`.

The features pass the same night (11 picks, branch `upstream-group2`; the owner took all of B):

- Tab switch on the press (`4ad54a1`): a press on one of several picked tabs waits for the release
  (`SidebarRowPress.keepsPicksOnPress`), so a drag from it still carries every pick; scenario `sidebar-press`
  drives rows through their own mouseDown/mouseUp (`cra://debug?pressRow=`).
- Instant Links (`426c345`, `20de2af`): the switch sits in `pane://settings` ▸ Max after Tidy Tabs, with its
  picture and the footer's line about searches; `SettingsBridge.editableKeys` has it; the SwiftUI `MaxPane` and
  the `Sharing.swift` key list are not in Pane. The command bar keeps Pane's look and tones; only Shift-Return is new.
- Links dragged into the sidebar (`115a201`…`a4192fe`) follow Pane's sections: into a section on its tabs or
  header, after it on its end line (┄); `drop-link-sections` checks them and a section drag after
  (`cra://debug?dropLink` gains `endOf=`). `Easel.webAddress` comes alone in `EaselWebAddress.swift` (upstream has it
  in `EaselObjects.swift`, from the skipped `e4b7447`).
- Split by drag (`60cf686`, `2908a25`): a Library bookmark's drag is never a split, so Pane's page drop (new tab,
  ⇧ this tab) keeps it; `split-drop` checks one at a pane's edge. Each press clears `tabBeforePress`. The drop
  region is rounded as a split's pane; Pane's toolbar inset replaces upstream's `barInset` (auto-hiding toolbar).
- `favorite-mute` now expects Pane's shared-favorite menu (Rename…, Mute, …, Remove Favorite), the owner's call.
- Found while checking this pass, a bug from the CEF pass's spare pages (`935cca1`): making a spare took the keyboard
  (Chromium makes the window it shows key), so the URL field's dropdown closed when one came while it was open.
  While a spare is made, Chromium's windows can't become key (`SparePages`, Pane's own commit after `935cca1`).

The iPhone pass (14 Nov 2026, 65 picks, branch `iphone-app`; the owner took the app, skipped on 13 Nov):

- Internal names stay Cra's (`iOS/Cra.xcodeproj`, the Cra, CraShare and CraWidgets targets and folders), as on
  the Mac, so upstream's later iPhone commits still apply; what people see says Pane (the owner's call). Bundle ids
  `uz.pane.ios`, `.share`, `.widgets`, `.uitests` on team GWSB8L799B; `pane://` links; copy through `Brand.name`.
- GWSB8L799B is a free Apple team: no iCloud container, no App Group. The phone reads the Mac's Spaces from the
  folder the Mac syncs into in iCloud Drive, picked once in Files (`SyncedSidebar`, the owner's call); the share
  inbox is a Keychain item in a group both targets claim (`MobileShareInbox.updateInKeychain`). The Mac app's
  entitlements don't change.
- Icons: Pane's, from `scripts/make-app-icons.swift --ios` (Arctic, Midnight, Graphite, Rose, and Pane's mark);
  upstream's `--ios` mode (Cra's icons) was not taken. `MobileTests`' sample Mac space has a colour preset, as Pane
  starts spaces unthemed. `scripts/ios.sh device` installs onto a connected iPhone with Xcode's free-team signing.

The 16 Nov 2026 sync (14 picks and a hand-port, branch `upstream-sync-nov16`, all on CEF; the owner took groups
1–3 of the triage but Tidy Tabs and the engine-only tests) adapted these:

- Tidy Downloads (`1b0634c`): Arc 1.173's nine examples replace the made-up ones Pane had renamed for its brand.
  `test-tidy-downloads.sh` builds on CEF with Pane's `AppComposition`, `FeatureFlags` and `ChromeDownloadAnimation`.
- Ask on Page (`dc7e3ef`): the CEF bridge's find correlation and isolated-world evaluation only (the engine's
  `bridge.mm` is Pending E). The card and find bar sit under Pane's fixed toolbar: no `floatingToolbarCover` or
  `FindBarPlacement` (the auto-hiding toolbar, `167c05a`, is skipped), and the floating-toolbar selection test is
  left out. Pane has no master Max switch, so the lifecycle harness takes its six-feature sequence from the Max
  card's rows in `settings.js`. The locked #393/#417 tests on the old `<excerpt>` format are replaced as upstream's
  (Victor's call); `promises.lock`'s #393 and #417 rows equal upstream's.
- 5-Second Previews (`234639e`): redirect hops checked and the profile's cookies never sent to a local address,
  as upstream. Without Tidy Tabs #443 its `tidyTabsChanged` hooks and `cancelAll` stay out.
  `TabRuntime.pageScreenFrame` comes from the engine's `6f29b6d` (on CEF: the page's Chrome window frame, or a
  WebKit page's view).
- Data folder owner (`2f5e3b0`): the Keychain step (`SafeStorage`, "Pane Safe Storage") still waits until no other
  Pane runs; only the folder's own migrations follow Chromium's `SingletonLock`.
- Import (`64b20c0`): the Full Disk Access note says `Brand.name`. #447 (`2507db1`): the iPhone page cover stays
  above a popup's web view. Blocker (`f11c0eb`): the #308 checklist line beside it stays out with `7be55ee`.
- Find bar per tab (`8cc7ac7`): its scenario reads `cra://debug?findBar=`, which upstream made with the auto-hiding
  toolbar (`720ede7`, skipped); the readout alone comes in with the pick. The dock snapshot (`89982b1`): upstream's
  re-recording equals what Pane draws after the `EmojiLabel` hand-port, byte for byte.
- Snapshots that already differed before this sync and still do (report-only): `download-rename-long`/`-short`
  (recorded 5 Nov on a dark space; Pane's new spaces start light) and `download-preview-dock` (1.8 %).
- Upstream has no counterpart for Pane's own fixes of the same day: a space coming back where it was scrolled
  (`79ea4d67`) and the downloads list above the mini player's cards (`9bf42d58`).

The Chromium engine pass (16 Nov 2026, the 103 commits, branch `chrome-158`): Pane runs on upstream's published
Chrome 158 engine (`scripts/fetch-engine.sh`, `engine-158.0.8127.37-12`), which is Cra's build, rebranded at build
time rather than built from Chrome's source. `CRA_ENGINE=cef scripts/build.sh` still builds on CEF (156, `codecs7`).

- Keychain: `scripts/cef-keychain-item.py` renames the engine's item to "Pane Safe Storage" / "Pane" unchanged (the
  code that copies the names has CEF's shape; 2 + 2 places). Checked at runtime on a clone of the owner's profile,
  network off: under lldb the framework's own `SecItemCopyMatching` asks for `svce = "Pane Safe Storage"`,
  `acct = "Pane"`; no Keychain prompt; 700 of 702 cookies stayed (every site kept its own; the two gone were week-old
  `googtrans` session cookies), all still `v10`. The profile had no saved passwords or cards.
- `build.sh` gives Chrome's helpers Pane's names, icon and ids under `uz.pane.browser`; the Alerts helpers are "Pane"
  with Pane's CEF Alerts id (`uz.pane.browser.helper.alerts`), so notification permission carries over.
- Pane's own CEF bridge calls the engine doesn't have: `browser:didLoadFavicon:forURL:` is declared again (the engine
  calls it unconditionally); `setHardwareAccelerationEnabled` and `setBoostScript` are called only where the bridge
  has them; the Boosts' start script goes in with the engine's own start scripts and, in pages made before a change,
  over each page's DevTools session (`EngineBoostScript`); a favicon Chrome didn't find is searched by `FaviconFinder`
  a second after the load, fetched without cookies (`FaviconFetch`); `cra://debug?windowCorners` reads the page and
  DevTools views in the card. `peekSource` keeps Pane's (upstream's builds on the skipped `8f9af14`) and finds the
  page by `pageWindow`/`pageScreenFrame`. The engine half of `dc7e3ef` (Ask on Page's find and evaluation) came in
  with these, so `engine/` and the pin equal upstream's.
- A page Chromium makes itself and a tab takes (a link's new tab from ⌘-click, `target=_blank` or Chrome's page menu,
  a page's pop-up) came into the tab white on the engine, found by the owner the same night: the page ran (its sound
  played) but nothing showed, it took no clicks (no page menu), and a reload changed nothing. Two causes, both views
  (17 Nov 2026): Chromium's own view of the page (`WebContentsViewCocoa`) arrives hidden, as Chrome's window hid it
  as a tab behind, and Pane shows it with its tab (`BrowserManager.showChromiumPageView`); and a link's tab opened in
  front was shown as Chromium handed its page over, before the window had its card, so the page stayed in the holder
  for hidden pages, and the window now shows tabs again while a page isn't in its card (`hasUnplacedPages`).
  Upstream's `BrowserManager` and window code are the same, so its engine likely has both. Scenario
  `link-new-tab-loads` checks the view (`cra://debug?pageRect`) and, when the window is on screen, its pixels
  (`expect-pixels`); a first fix by focus emulation (`62f69342`) made the page think it was shown, not the view.
- Checked on the engine: `scripts/test.sh` and lint; 188 of 207 scenarios in one run and 6 more on a rerun; the Mac
  half of `scripts/ios-sync-e2e.sh` (folder sync). The 6 that take over the screen were not run (the owner's call).
  `instant-links`, `little-window-devtools` and `permission-card` fail on CEF's main as well (not the engine's).

**Known limitations of the prebuilt engine** (Pane's own build of the engine would lift them):

- A brand-new tab's first document on a boosted site parses before its boost is on (zapped elements show until the
  load commits): the engine's start scripts miss the first document of a page made and loaded at once. Reloads,
  navigations, a tab that takes a spare and every later document start boosted. `boost-zaps-on-load` fails its
  first check on the engine (it passes on CEF).
- Activity Monitor lists Chrome's helpers as "Cra Helper (…)": Chrome finds them by a name compiled into the framework.
- Settings' "Use hardware acceleration" does nothing on the engine: its bridge starts Chrome with the app's own
  arguments and has no call for `--disable-gpu`.
- The page menu has no "Open Link in Peek" (⇧-click still peeks) or "Open Image in Preview": they were Pane's CEF
  bridge's items.

### Hand-ported (6): Pane's own code after the upstream commit

| Upstream | Pane | What |
|---|---|---|
| `c1aadf7` | `6adf062` | Theme editor: − on the last colour goes back to the unthemed default (#300) |
| `b4c20de` | `f2f1840` | Settings: a line under each setting saying what it changes |
| `eda6089` | `77e2fa1` | Copy URL glyph: link → checkmark → link on a click (#361) |
| `2d7e110` | `ee8e0f6e` | One repo for both apps: the iPhone app in the README, CONTRIBUTING, CLAUDE.md and CI (not upstream's issue forms) |
| `7b702b1` | `a2177a75` | Emoji label draws into a finite rect, so the space dock's snapshot keeps its emoji (only this hunk; the rest of the commit is the Chromium engine's, Pending E) |
| — | `f166b35` | Extensions popover and bookmark card follow the space's light or dark (upstream's idea, Pane's SpacePopoverTones; no single upstream commit) |

### Covered by Pane's own work (7): the behaviour is in, by another route

| Upstream | Why it isn't picked |
|---|---|
| `fb2c304` | Full screen with the sidebar hidden: Pane's WindowFill / fullscreen sidebar does it |
| `43e8adc` | ⌘S slides the sidebar, page and toolbar stay put (#317): Pane's docking motion |
| `b58b69d` | Library pushes the page past the window's edge (#340): Pane's Library drawer |
| `f5751d6` | ⌘W closes Settings (#364): Settings is a tab in Pane, so ⌘W already closes it |
| `537dc09` | Notes for #364 on SettingsWindowController, which Pane doesn't have |
| `f3cf96e` | Docked page and DevTools corners square on macOS 27 (#400): Pane's ChromiumWindowCorners re-masks on 27 (11 Nov), scenario devtools-square-corners |
| `4cf04e2` | Floating sidebar: no pointer timer while the sidebar is anchored: Pane's `FloatingSidebarPoll` (CraCore, since `09a551c7`, 11 Nov) already stops it with the sidebar docked, and slows it to 4 Hz at rest |

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
| `1fd954f` | Mouse back/forward over the sidebar reach the Library before the first space (#233) | Owner's call (12 Nov sync) |
| `9dd665f` | Share N Items…: "N Items" title, "Copied Folder URL" toast (#356) | Owner's call (12 Nov sync); its links are crabrowser.app's |
| `8d1f2b9` | Zap as in Arc 1.172.2: confirm popover, shelf of zapped elements | Owner's call (12 Nov sync); collides with ShellView's docking and drawer code |
| `761153e` | Boosts gallery: Share Boost… and Open in Cra from crabrowser.app/boosts | Owner's call (12 Nov sync); depends on upstream's site |
| `e4b7447` | Easels: Arc's colours, picker, menus, undo, link cards, live captures | Owner's call (12 Nov sync) |
| `b478731` | Profiles: per-profile "New documents" app and a "New Google Doc"-style command (#375) | Owner's call (12 Nov sync) |
| `0b20792` | Spaces: a PNG or SVG as a space's icon (#395) | Owner's call (12 Nov sync) |
| `167c05a` | Toolbar: "Hide the toolbar until you need it" (not in Arc, #405) | Owner's call (12 Nov sync); not in Arc |
| `80cdfe7` | Settings back in a native 684 × 650 window with ten tabs, member card, "Share Cra" (#372, #377) | Pane's Settings is the `pane://settings` tab |
| `caaa884` | Settings' first tab carries the user's first name (#372) | Needs `80cdfe7` |
| `8f146f3` | Command bar: rows under a still pointer keep the top row selected (#382) | Command bar: never touch |
| `ffd7de6` | Themes: dark colours without the purple cast (#392) | Pane's theme pipeline (default tint, opacity, new-space tones); changes every dark space |
| `02d8f9a` | Themes: Dark keeps the picked colour (#392) | Needs `ffd7de6` |
| `904c9ca` | Themes: Light keeps the picked colour (#392) | Needs `02d8f9a` |
| `ed26238` | Peek: ⌘S toggles the window's sidebar, the Peek follows the slide (#402) | Collides with ShellView's docking and full-screen sidebar |
| `f13c956` | Updates: the downloaded update runs once, hidden, so its first launch doesn't wait for ma… | Pane has no update feed (Sparkle's SUFeedURL is removed), so a downloaded update never runs this |
| `4967f24` | Speed: the bench that measured this round (scripts/perf) and what the next gains need (do… | Upstream's perf bench (scripts/perf, docs/speed.md); Pane measures with scenario budgets |
| `2165ca1` | Updates: the warm-up runs the helper apps too, so the first launch after an update is as… | Goes with `f13c956`: no update feed in Pane |
| `ae7afb5` | Speed: journeys on a real sidebar and real sites, and where a tab switch's time goes | Upstream's perf bench and docs/speed.md |
| `55f5549` | Speed: plain Chromium 156 from the same tree uses more memory than Cra; tonight's results… | docs/speed.md and a plain-Chromium perf patch |
| `729d671` | Speed: CEF 158 exists as a beta branch (8127); Cra waits for stable | docs/speed.md: CEF 158 beta note |
| `b309829` | Release notes: sponsors are thanked first, at the top; sponsors.py reads the sponsors fie… | Upstream's release notes and sponsors |
| `a531a29` | Speed: what the browser process spends per tab, new-window time, no other dirty libraries… | docs/speed.md |
| `720ede7` | Auto-hiding toolbar: the find bar hangs under the toolbar while it is out, not over its r… | Needs `167c05a` (auto-hiding toolbar), skipped |
| `d455cb4` | Tidy Tabs: Arc's grouping prompt, stable group ids, fitted requests (#443) | Owner's call (16 Nov sync): Pane's Sections keep their own Tidy (Tidy Tabs Behavior, the Today divider, undo/redo) |
| `3681a95` | Tidy Tabs: one group name per tab, Arc's empty-run rule (#443) | Goes with `d455cb4` |
| `8860fc3` | Locked tests for #208, #36, #111, run on the engine; engine -5 | Owner's call (16 Nov sync): tests only, written against the engine; the engine is in since the same day, so they can come now |
| `392cc7e` | Locked test for #106 on the engine (extension badge and title) | Same as `8860fc3` |
| `01c002b` | Locked test for #198 on the engine (auto Picture in Picture on leaving a call) | Same as `8860fc3` |
| `72b25f2` | xbench: the cross-browser bench (Cra, Helium, Arc, Dia) | Upstream's perf bench (scripts/perf); Pane measures with scenario budgets |
| `335bb79` | xbench: read the URL back before Return; a probe mode | Goes with `72b25f2` |
| `bfdbacb` | xbench: the method, written for anyone to rerun | Goes with `72b25f2` |

### Superseded by a squashed commit (66): Varun's branch commits, merged tree-neutral (16 Nov 2026)

Upstream merged #439–#448 as squashed commits (`1b0634c`, `d455cb4`/`3681a95`, `2507db1`/`39615a1`, `dc7e3ef`,
`234639e`, `11e4dec`); each "Merge #…: its change landed as …" has the tree of its first parent, so these
commits add nothing the squashes don't.

| Upstream | What |
|---|---|
| `a75d7bd` | docs(downloads): plan Arc rename parity |
| `3012f06` | docs(tabs): plan Arc grouping parity |
| `5de4d1d` | docs(previews): plan Arc preview parity |
| `a9baa45` | fix(downloads): preserve Arc filename suffix rules |
| `2b8812e` | docs(ask): plan Arc page questions |
| `529308b` | fix(downloads): match Arc collision naming |
| `bf795a0` | fix(previews): scope caches to browser context |
| `2c23473` | fix(tabs): preserve group identity during tidying |
| `c00d0a8` | feat(ask): add grounded page dialogue logic |
| `6c64894` | fix(tabs): keep unseen tabs eligible for tidying |
| `30c01a7` | feat(ask): capture bounded current-page context |
| `e20d7ea` | docs(tabs): align singleton plan with Arc evidence |
| `d4e1c29` | docs(ask): adapt output plan for on-device generation |
| `8fb00bd` | fix(previews): own hover request lifetimes |
| `74b9757` | docs(ask): preserve answers with missing emphasis |
| `2211deb` | feat(tabs): match Arc grouping prompts and context limits |
| `904aee1` | feat(ask): stream grounded on-device answers |
| `e08c73d` | docs(ask): define correlated native Find sessions |
| `f9225de` | feat(downloads): match Arc rename prompt context |
| `2fc13c5` | fix(previews): bound and cancel native requests |
| `ea28e08` | feat(ask): correlate native Find sessions |
| `2356949` | docs(ask): reconcile upstream and legacy contracts |
| `bb69453` | fix(downloads): cancel obsolete rename requests |
| `15b125c` | fix(downloads): reconcile file moves and undo |
| `6de2bed` | fix(previews): bound optional image requests |
| `ee8699f` | fix(tabs): preserve retries and cancel stale grouping |
| `a4f573c` | feat(previews): match Arc prompt and optional summary fields |
| `26b6eea` | fix(ask): revoke changed page ownership for #393 |
| `bae07fd` | fix(previews): fit model context and recover one overflow |
| `b05e45c` | fix(ask): locate exact live page quotes for #393 |
| `7dfbb4b` | test(downloads): verify native rename and undo |
| `d562830` | test(tabs): verify grouping and native undo |
| `310b84a` | fix(previews): revoke unavailable preview work |
| `11dc9d4` | fix(ask): match native input and card layout for #393 |
| `653ed22` | fix(ask): import standalone geometry for #393 |
| `3db3148` | docs(previews): record validation and native acceptance limits |
| `822e3ba` | test(ask): verify renderer and Find lifecycles for #393 |
| `6ad6dc5` | docs(ask): record native Find engine validation |
| `2d7075c` | fix(ask): restore readable native Find controls |
| `229edfe` | docs(previews): record deferred native hover validation |
| `5c91655` | fix(ask): reveal new questions after conversation layout |
| `a99ac85` | docs(ask): record native input and quote validation |
| `c05b065` | refactor: simplify private Ask DOM bookkeeping |
| `b18cbe5` | refactor: avoid copying bounded tidy candidates |
| `c9dae9e` | refactor: remove unused preview imports |
| `80dc0e2` | refactor: remove unused iOS store callbacks |
| `adf389a` | refactor: remove redundant download request state |
| `126df4e` | fix: find early citations in bounded page prefixes |
| `e47da6a` | fix: bound preview share image allocations |
| `205b937` | fix: preserve literal plus signs in search queries |
| `a86b572` | fix: preserve related iOS popup navigation and opener ownership |
| `5d4b15c` | fix: preserve download ownership across path replacement |
| `52529b2` | fix: retain download ownership across replacement and tab transfer |
| `7d6b943` | test: normalize dialog snapshots to srgb |
| `c2998e2` | test: normalize dialog snapshots to srgb |
| `c2351ff` | remove branch documentation changes |
| `dcd6b9c` | remove branch documentation changes |
| `4f7a71f` | remove branch documentation changes |
| `32675b1` | remove branch documentation changes |
| `aad2c31` | remove branch documentation changes |
| `bd5de9a` | remove branch documentation changes |
| `df3683b` | remove unused history move result |
| `2aac4c1` | remove one-off tidy tabs test selectors |
| `ea428cf` | remove redundant preview model accounting and test selectors |
| `97f4e07` | remove unused ask source storage and duplicate emphasis lookup |
| `5c1a3f5` | remove unused download test paths and optional source state |

## Pending

None: every upstream commit through `f8a6402` is Ported or Skipped (16 Nov 2026). New upstream commits go here
when triaged, sorted as before: A (bug fixes, engine, tests: small, low risk), B (new features) and C (collide
with Pane's own UI), each row with the files it would conflict in on main (`scripts/upstream-audit.py --conflicts`)
and the earlier pending commit it needs.
