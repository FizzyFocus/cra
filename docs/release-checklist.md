# Release checklist

Most closed issues are pinned by a locked test (rule 8 in [testing.md](testing.md),
`Tests/promises.lock`). This page covers the rest: what only a person can check in a real
window (a real site, the GPU, full-screen Spaces, how something feels), and the issues still
waiting for a hook or a move into CraCore before a test can pin them.

Before tagging a release, run through the checks for every area the release touched, on the
built release app with a test profile. Note anything that fails in the release's issue or PR.

## Manual checks

### Themes and window chrome

- **#155:** a space on Auto, with one colour or two, changes look when macOS switches between
  light and dark. A space on Light or Dark doesn't.
- **#37:** over scrolling text, the sidebar stays blurred in every frame, with no hover.
- **#83, #132:** activating the window shows a flat fill for a moment, never a sharp unblurred
  frame. In full screen a solid space sits on the wallpaper tint, not near-black.
- **#156:** with Reduce transparency on, the sidebar is one flat colour across activations and
  swipes. With it off, a Dock restore and Stage Manager show no matte frame, and a ⌃←/⌃→
  full-screen round trip doesn't step.
- **#46:** waking a slept tab in dark mode shows a black page area, not white.
- **#6:** a new window's empty card has rounded corners.
- **#24:** edge to edge, there is no margin and the card is square, with the sidebar shown and
  hidden.
- **Maximized (WindowFill):** with the setting off and the sidebar docked, ⌥-click the green button
  (or double-click the title strip): the card keeps its margin, outline and rounded corners beside
  the sidebar; so does full screen (⌃⌘F). Hide the sidebar (⌘S) while maximized or in full screen:
  the card goes edge to edge as the sidebar slides away, and back into its margin as it comes. With
  the sidebar hidden, ⌥-click the green button and, with System Settings ▸ Desktop & Dock ▸
  "Double-click a window's title bar to: Fill", double-click the strip above the page: the window
  starts growing at once, and the card's margin, corners and the toolbar's sidebar toggle move with
  it on the same curve, landing with it; restoring runs the same way back. No pause, no jump. With
  DevTools open the card keeps its margin in a window; in full screen with the sidebar hidden or
  floating, the page and DevTools go flush to the screen's edges with no margin, outline or rounded
  corner, meeting each other on DevTools' own 1 pt line (11 Nov 2026), and step back into the inset
  card when ⌘S docks the sidebar. Rest the pointer on the toggle until
  its tip shows, then zoom: the tip goes at once and never hangs over the address field (also
  entering and leaving full screen).
- **Video full screen:** with the sidebar docked, play a YouTube video full screen: the sidebar goes
  and the video fills the screen. Touch the screen's left edge: the floating sidebar slides in over
  the video and leaves with the pointer. ⌘S: the sidebar docks on the left and the video's card
  steps in from the edges with the usual margin, outline and rounded corners (Arc 1.172), the
  address pill reading "Exit Fullscreen" (⤡); ⌘S again: the video fills the screen once more.
  Click Exit Fullscreen or press Escape: the window is back exactly as it was, sidebar docked.
  Again with the sidebar hidden: it stays hidden after.
  With the video in full screen, click another tab in the floating sidebar, press ⌘T, or open a link
  from another app: the video leaves full screen first and the window is back to its own layout.
- **Full screen:** entering, the sidebar toggle glides left into the traffic lights' place;
  leaving, it glides back right before the lights reappear, never under them. With the sidebar
  hidden, the edge reveal shows no traffic lights in the sidebar.
- **No tab:** with every tab closed, the empty card says No Tab Open and the New Tab shortcut, light
  and dark, with the sidebar shown and hidden.
- **#10:** neighbouring tab highlights keep a 5 pt gap.
- **#11:** the Library glyph is centred in its hover square.
- **#39:** the header chevron is about 12.5 pt and points right when the pinned tabs are
  collapsed.
- **#31, #48:** the tab-list scroller shows a 4 pt knob 3 pt from the edge with "When
  scrolling", and a 5 pt knob with "Always".
- **#189:** colour swatches grow on hover and shrink when pressed; "Back to Pinned URL" slides
  in over 0.16 s.
- **#88:** importing from Arc copies its Show Full URL setting.
- **PR #269:** in Settings, the selected source-list row is inset 10 pt from both sidebar edges
  (glyph 20 pt and label 49 pt from the edge, as in Dia 1.55.1), and scrolling Performance or Advanced
  never draws under the back/forward pill or the pane title.

### Sidebar, tabs and the command bar

- **Global favorites:** with three spaces on one profile, swipe, press ⌃1–⌃3 and click the dock:
  the favorite tiles never move, fade or reload; only the open tile follows the space. A space on
  another profile cross-fades its own list in. Scrolling a long tab list never moves the tiles.
  A favorite's menu ends with a line, then Remove from Favorites (Remove Favorite when shared).
- **New Tab hover:** hovering + New Tab fills the row exactly like hovering a tab row (colour,
  inset, corners); only with the ⌘T bar open does it take the selected tab's fill.
- **Create a Space:** New Space… (+ menu, ⌘-palette, Spaces page) opens in the sidebar in place of
  its content, the dock still under it, the window already in the new space's pastel; with the sidebar
  hidden it comes out first and goes again on Cancel. Return creates once a name is typed, Escape
  cancels and the space it was opened from has its own theme back. Choose a Theme opens the picker
  beside the sidebar on a spring, its arrow at the row; a second press on the row closes it. A new
  space starts on Pastel's sky blue, in Light.
- **Theme picker:** light card with black ink in Light (and before a colour on a light Mac), dark
  card with white ink in Auto and Dark; it switches as the sun / moon / sparkles are pressed. Edit
  Theme Color… from a space header, its •••, a dock icon or the tab list opens it at the sidebar's
  edge with its arrow level with where the menu was opened (near the window's top or bottom the
  card stays inside and the arrow moves along it); from a Spaces page card flush with the card.
  Closing (Escape, a click outside) shrinks it back into its arrow as it fades, never a cut.
  On a Force Touch trackpad, dragging the pad's handle taps as it lands on red, yellow, green,
  cyan, blue or magenta, the grey centre or a Pastel colour (and holds there for a few degrees);
  the intensity wave and Opacity tap every tenth; the grain dial steps dot by dot, a tap per dot.
- **Opacity:** in the picker, drag Opacity down: the window goes see-through over the blurred
  desktop down to ~20 %, and at the right end lands on fully opaque (a one-colour theme too). Quit
  and relaunch: the space comes back exactly as see-through. Switch spaces and back: it keeps it.
- **Space chevron:** clicking a space header turns its chevron a quarter on a spring with a hint of
  overshoot; clicking again mid-turn reverses it smoothly.
- **Folders:** opening one slides its tabs down from directly under its row, fading in, as the rows
  below are pushed down; nothing shows above the row's bottom edge, no title shows through the
  folder's name, and nothing flashes at its final place first. Closing slides them up behind the row,
  gone just before the gap closes. Toggle a folder quickly several times: it always settles with
  every row in place. Closing or opening a tab inside an open folder doesn't fold.
- **Manage Spaces:** on the Library's Spaces page, drag a card by its move handle past its
  neighbours: the card keeps its size (no zoom of its contents), each neighbour springs aside as
  its centre passes (a tick each), live while dragging; letting go springs the card into the gap
  and keeps that order.
- **Tab lines:** on a Today tab, ⌘-click three links: they line up below it in the order clicked
  (first link right under the tab). ⌘-click a link in the second one: it goes under that one, and the
  next link from the first tab goes after it. Drag the second tab elsewhere, then ⌘-click another
  link in the first: it goes under the first tab's remaining line. Each ⌘-click shows "New Tab
  Created" (its Show switches to the tab); so does a link opened from another app.
- **Unload Tab:** right-click a loaded tab that isn't open ▸ Unload Tab: its name dims to half and a
  dashed ring circles its icon. Click it: it loads at once,
  back and forward and the scroll position kept. Middle-click a loaded tab: the same (Settings ▸
  Tabs ▸ "Middle-click a tab to unload it" off: it closes, as before). Hold ⇧ over a loaded tab: its
  ✕ turns into a −, which unloads it. The open tab offers none of these.
- **Quit:** with Settings ▸ Advanced ▸ Warn before quitting on, ⌘Q: "Quit Cra?" once; Quit closes
  Cra without a second dialog. Same from the menu bar's Cra ▸ Quit Cra and the Dock's Quit.
- **Hover across spaces:** rest the pointer on a pinned tab in one space (it lights), switch space
  with ⌃2 (or a dock click, or a swipe) and back with ⌃1 without moving the pointer: no row, space
  header, chevron or ✕ is lit; move the pointer a little and what is under it lights.
- **Mini player:** play audio in a background tab: a slim pill of controls under the list. Hover it:
  only the card grows upward on a spring, showing the title, Picture in Picture and ✕, over the
  list's bottom; the tab rows behind don't move, scroll or jitter. Leaving, it folds back the same way.
  Picture in Picture from the card, pause in the floating window, close it: the card comes back
  showing ▶ (paused) at once. Play it in the floating window and close it with ✕ (which pauses it):
  ▶ again, not ❚❚.
- **⌘D on a favorite:** open a favorite, ⌘D: "Already in Top Favorites", nothing pinned; ⌘D again
  within 1.5 s: "Added to Pinned Tabs" and a copy appears in the space's pinned tabs. ⌘D on any
  other tab pins or unpins at once.
- **Bookmarks:** the address bar and pill have no star. Open the Extensions popover (sliders
  button): it is frosted (the page and desktop show through, blurred), not a flat grey; the top row
  is Share, Copy Link, ★, Screenshot, Capture, each a tile exactly the size and corner of the
  extension tiles under it, in the same columns. Click ★: the popover goes and
  the bookmark card springs in exactly as the Extensions popover does (the same popover, material
  and arrow, its arrow at the same place under the Extensions button) and springs out the same way;
  its three tiles are the Extensions row's tiles, spread over the row (first and last columns and the
  middle one), no blank run on the right. It looks like
  the Extensions popover (same panel colour, raised Copy Link / Share / Remove buttons, bold "Bookmark
  Added" and "Folder" headers, name, address and folder in grey tiles, a hairline, a "Bookmarked"
  pill and a dark Done pill), in light and dark mode. Type a new name, open the folder tile's menu
  (folders in their colours), hover "Folder" and click New Folder, type its name and press Return:
  the card stays open the whole time (and with the floating sidebar); Escape while naming the folder
  only drops the name. It closes on Done, Escape, Remove or a click outside it. Reopen the popover:
  the ★ is filled, in the accent colour. ⇧⌘D does the same from the keyboard. Window ▸ View
  Bookmarks… (Library ▸ Bookmarks, ~400 pt drawer): folders are drawn like pinned folders (40 pt
  rows, the folder glyph that opens, 14 pt title) with a chevron at the row's end; a click opens or
  closes one: the glyph opens, the chevron turns a quarter on a spring, and the folder's rows slide
  down from under its row (back up into it when closing) as the rows below move, the way a pinned
  folder does; remembered after a relaunch. An empty one shows "Folder is empty"; right-click a
  folder: New Subfolder…, Rename…, Icon Color ▸ (Auto, then ten colours with swatches), Delete
  Folder (asks when bookmarks would go); right-click the empty space: New Folder…; right-click a
  bookmark: Open / Copy Link / Edit… / Delete Bookmark, and deleting the last bookmark in a folder
  leaves the folder. Drag a bookmark onto a folder (or onto a bookmark inside it): it moves there and
  the folder row lights while it would take it; hold it over a closed folder: it opens; drop on the
  blank space: back to the top. The row under the pointer looks like a sidebar tab (40 pt, 14 pt
  title, no ✕, top level). On a Force Touch trackpad: a tick each time the drop would go somewhere
  new (another folder lights, the top). Drag a folder into another (never into itself). Drag a bookmark onto
  the page: "Open in New Tab" shows over the card and the drop opens a new tab; hold ⇧: "Open in
  This Tab" and the drop loads it in the tab on screen. Drag one to Finder or another app: a link.
  Hover: run the pointer up and down the bookmarks, fold folders under it, close and reopen the
  Library: one row at most is ever lit, and none once the pointer leaves the list. ⌘T and type part of a bookmark's
  title: its row says Bookmark. ⇧⌘D no longer hides the toolbar (View ▸ Hide Toolbar keeps its
  menu item; set a key in Settings ▸ Shortcuts).
- **Space swipe taps:** on a Force Touch trackpad, swipe slowly between spaces: one tap as the
  strip passes half way (and one if you drag back). Flick quickly: the tap comes during the flick,
  with your fingers still on the glass, every time; never two for one space.
- **Cold start:** with a dozen tabs, quit and reopen Cra: only the open tab loads (Activity Monitor:
  one renderer); every other tab's name is at half strength with a dashed ring round its icon.
  Click one: it loads then, and its row comes back to full strength.
- **Tab list scroller:** with System Settings ▸ "Show scroll bars: Always" and a mouse plugged in,
  scroll a long tab list: the knob floats over the rows and fades; tab and folder names never shift.
- **Dock:** right-clicking a space icon shows the header's menu; Rename Space… goes to that space and
  edits its name in place. Dragging an icon lifts it, the others spring aside with a tick each, and
  it springs into its slot on release.
- **Download bin and the downloads list:** download a file; its thumbnail sits up and to the right
  of the Library button. Hover the button: as the list opens, the thumbnail rises into the list,
  growing into the newest (bottom) row's thumbnail, and the button and its "View Library" tip are
  clear; move away: it comes back down into its place as the list closes.
- **Create a Space with the sidebar hidden:** ⌘S to hide it, then New Space…: the sheet comes out in
  the floating sidebar, which stays out while you type and pick a theme (the picker beside it);
  Create Space or Cancel: the sidebar is hidden again (floating while the pointer is on it), never docked.
- **Theme picker:** New Space… ▸ Choose a Theme: the pad has no colour on it ("Tap to pick a color
  for this space"), the new space unthemed (light grey) until one is picked; + puts Pastel's sky blue
  on the pad, – takes colours off down to none. The card's arrow stands out of its left edge at the
  row (or the space header) it points at, the same rounded shape as the Extensions popover's, with
  the card's shadow, never clipped.
- **Settings tab (⌘,):** ⌘, opens a tab at cra://settings with a gear icon (no overlay, no window):
  General, Search Engines, Appearance, Tabs & Spaces, Shortcuts, Privacy, Advanced, then under More
  Profiles, Extensions, Plugins, Max and Performance, all in the same page (no other window opens).
  Groups sit about 30 pt apart, each a rounded card with roomy rows. ⌘, again brings that tab back, on
  the section asked for. It follows macOS light and dark (Websites ▸ Light/Dark set it). Toggles,
  menus and the opacity slider write at once, and a change made elsewhere (View ▸ Show Toolbar) shows
  without reloading. General has Sync (iCloud, a folder, Export…/Import…) and the App Icon tiles;
  Tabs & Spaces has Air Traffic Control's routes inline (New Route, Contains/Is equal to, Open in a
  space or a Little Window). Profiles: Rename…/Delete… ask on the window; per-profile downloads and
  languages. Plugins: switches, Add Plugin… asks before installing. Performance refreshes every 2 s
  while shown. Shortcuts: click a row, press keys (⌘T included); Escape cancels, Delete clears;
  Reset All asks first. ⌘W closes the tab like any other.
- **Settings ▸ Shortcuts:** a filter field and Reset All in a header row like the other pages, then a
  rounded card per group (Cra, File, Edit, View, Navigation, Tabs, Split View, Spaces, Archive, Window,
  Developer…), each shortcut as macOS key caps, one per key (⇧ ⌘ D), light and dark. Click a row:
  "Type the new shortcut" breathes in the accent colour; a changed one says "Changed" with a reset.
- **Dialogs in the space's colours:** on a light pastel space, ⌘Q (Quit Cra?), Delete Space, Spaces ▸
  Change Profile and Settings ▸ Profiles ▸ Create Profile…: each is the same card, pastel and a little
  frosted with dark text; on a dark space the space's own dark tone (not flat navy) with light text.
  Shapes, type, spacing and the blue/red buttons are unchanged. Settings' Rename…, Delete…, removing or
  adding a plugin, importing settings and Reset All ask in that same dialog.
- **Energy (11 Nov 2026):** with Cra frontmost and idle (sidebar docked, a page loaded, pointer still)
  for a few minutes, Activity Monitor ▸ Energy shows Cra and its helpers near 0 and macOS's battery menu
  doesn't list Cra under "Using Significant Energy". With the sidebar hidden, the edge still reveals it
  at once after the pointer has rested. Settings ▸ Performance shows numbers while open ("Measuring
  while this page is open") and cra.log says recording stopped a few seconds after leaving it.
- **Escape keeps the window's size:** maximize (⌥ green button or title bar double-click) and, separately,
  enter full screen (green button); press Escape with nothing open, with a page focused and with the
  sidebar focused: the window stays maximized / full screen. With the command bar, a popover or the find
  bar open, Escape closes that; a video in full screen leaves full screen.
  On cra://settings, maximized and in full screen: Escape with nothing focused does nothing; in the
  search or Shortcuts filter it clears and leaves the field; with Add Site Search open it closes that.
- **Default color:** a space with no colour of its own (a new one) is Arc's pastel sky blue, see-through,
  not white. Settings ▸ Appearance ▸ Spaces ▸ Default color: the chips (or any colour) repaint every
  such space at once; the reset arrow brings the sky blue back.
- **Search engines, full control:** every engine and site shows its icon (fetched from the site the
  first time when Cra has none; Google's G is Google's logo). Each built-in site has edit (opens the
  dialog filled in; saving adds your copy and takes the built-in off) and remove; Restore Removed (n)
  brings them back; a removed site's Tab no longer offers it in the command bar.
- **Site searches:** Settings ▸ Search Engines ▸ Add Site Search…: name YummyAni, shortcut ya,
  query URL https://yummyani.me/search?word=%s, "Its own color" off (the dialog's badge preview grey). In the command bar type "ya": "Search YummyAni
  Tab" shows; Tab: the chip reads YummyAni in the site icon's colour; type and Return searches there.
  Pick a colour for YouTube in the Sites list: "yo" then Tab shows the chip in it; Reset brings
  YouTube's red back.
- **Bookmarks import:** Library ▸ Bookmarks ▸ Import (the button beside the search): choose a
  bookmarks.html exported from Chrome or Safari: its folders appear, a toast says how many came in;
  importing it again: "Already Up to Date". Import bookmarks in Chrome's way (chrome://bookmarks ▸
  Import, or chrome://settings/importData): they appear in Library ▸ Bookmarks within a second or two;
  delete one in Cra and quit and reopen: it stays deleted.
- **Swipe to create a space:** on the last space, two-finger swipe on toward the next: a + in a ring
  appears at the sidebar's right edge, the ring filling as you go with a tick each quarter (Force
  Touch trackpad); let go full: Create a Space opens; let go short: nothing.
- **URL field dropdown:** click the sidebar's URL field (and, with the toolbar shown, the toolbar's): a
  narrow dropdown (about 360 pt) lies over the field, its text where the address was and selected,
  suggestions and history running down from it, smaller type than the palette; never the full
  palette. ⌘T and ⌘L open the wide palette in the middle of the window.
- **Loading bar:** load a slow page in a normal window: the pill pulses in the margin above the card,
  widens into the track and sweeps. Maximize the window and hide the sidebar (edge to edge): the bar
  still shows, just under the window's top edge over the page; a video in full screen has none.
- **Unloading a tab:** Unload Tab on a loaded tab on screen: its name and icon fade to half over
  about a third of a second while the dashed ring draws in round the icon; opening it again fades
  them back and the ring out. Right-click a tab ▸ Load on Start (ticked): quit and reopen; within a
  couple of seconds its row is no longer dimmed (loaded behind), and it never sleeps.
- **Tips, picks and background loading (11 Nov 2026):** on a light space, rest on a tab with a long title:
  the tip is pale and frosted with near-black text, "Double-click to rename" dimmer under it and a fine
  dark edge; on a dark space it is Arc's dark tip in the space's colour. ⌘-click two tabs, then click a
  third without keys: only it is selected; ⌘-click two again and click empty list space (or press
  Escape): none. ⌘-click two again and click the space's name, a section header (Pinned, Today),
  the gap between sections or the sidebar's padding: none either (a click on a tab still picks it).
  ⌘-click a link (background tab) on a slow site: its row's favicon dims with a three-quarter arc
  spinning clockwise round it, 1.5 pt, solid at its head and fading out along its tail, which fades as
  the page finishes and the favicon comes back to full strength.
- **Downloads open in the preview (11 Nov 2026):** start a download on a real site (a picture, a PDF):
  only Arc's navy glyph flies to the Library button, never Chrome's white circle with its download
  icon beside it. Click a picture in the tray over the Library button: Arc's preview grows out of the
  row's thumbnail over the dimmed window, the tray staying out behind it; the header is a light frosted band with
  dark text (✕ ‹ › name, age, ⋯, "Open in Preview ↗") over the blurred picture. ← → and ‹ › step
  through the tray's other files; a PDF, a Word file and a CSV show in Quick Look (↑ ↓ and the
  trackpad scroll them), a video plays with Arc's round button and its white progress ring (Space or
  a click pauses; the button fades while it plays and the pointer rests), a WebM plays in its own
  player. Esc or a click on the dimmed window shrinks it back into the row's thumbnail (the row of
  the file it shows by then), and the tray waits 3 s for the pointer before it goes; with the sidebar
  floating and the pointer away from it, the sidebar slides away with the tray as one. ⋯ has the download's menu
  (Hide from Cra drops the file from the preview). A ZIP or a disk image still opens in its app. The
  same from Library ▸ Downloads (newest first) and Library ▸ Media.
- **Animate sidebar docking (11 Nov 2026):** Settings ▸ Appearance ▸ Sidebar, off by default: ⌘S
  snaps the sidebar in and out as before. On: it glides (about 0.4 s) and the card eases into its
  inset frame and back to the window's edges, from the floating sidebar too, the page moving with
  its card and the window buttons fading on the same timing; nothing jumps at the end.
- **Preview: origin, zoom, web images (11 Nov 2026):** in Library ▸ Media and ▸ Downloads, click a
  picture: the card grows out of that exact thumbnail (not a corner or the side of the window) and
  Esc shrinks it back into it. Pinch on the trackpad zooms the picture, a double-click goes to 100 %
  at that point and back to fitting the card, a drag pans it while zoomed (an open hand), and closing
  a zoomed picture still lands in its thumbnail. On a web page, right-click an image: "Open Image in
  Preview (⇧-Click)" sits under Open Image in New Tab and opens it in the card, grown out of the
  image on the page; ⇧-click an image that isn't a link does the same, while ⇧-click on a linked
  image still opens the link in Peek. ⋯ has Copy Image, Copy Image Address and Save to Downloads.
- **Downloads tray clicks:** with the tray open, click in the gap between two rows or beside them:
  nothing happens (no tab under the tray opens or gets picked); the Library button below the last
  row still works.
- **⇧⌘L and ⌘L with the Library in the floating sidebar:** hide the sidebar, keep the pointer on the
  page and press ⇧⌘L: the Library opens in the floating sidebar. Move the pointer onto it and press
  ⇧⌘L again: the Library slides back to the space's tabs exactly as its ← does, the floating sidebar
  staying out at the sidebar's width, never cut in half. With the pointer back on the page, ⇧⌘L
  takes the sidebar away with the Library in it. With the Library open and the pointer on it, ⌘L
  slides it back the same way and the address opens on the sidebar's field; text typed at once
  lands in the address.
- **Docking glide's page:** with Animate sidebar docking on, ⌘S from floating or docked: the page
  resizes with its card through the whole glide, its content never snapping to the new width
  ahead of the card.
- **Card corners and docked DevTools (11 Nov 2026):** the page card's corners are 6 pt everywhere
  (docked, split, maximized with the sidebar shown), not the system's rounder window corners. Open
  DevTools docked right: the page's right edge meets DevTools in a straight line with only DevTools'
  own 1 pt divider between them (no dark edge, no light wedge in the corners), and the card's outer
  corners are single 6 pt curves (no second, larger curve behind them).
- **Downloads tray:** hover the Library button with downloads listed: the rows glide up into place on a
  spring and fade in (bottom row first) and settle back down as the list closes. Each row is Arc's: a
  40 pt picture with the same 6 pt round it on every side inside a rounded pill 8 pt in from the
  sidebar's edges (a Word or ZIP icon drawn whole, a preview filling the square), names and ages
  lined up on every row. The last row sits about 10 pt above the dock; moving slowly from the Library
  button up to the rows never closes the list. Only the row under the pointer lights; resting on one
  shows its whole file name beside it, and no tab tooltip or tab hover shows through from behind.
- **Gmail and Calendar previews:** on a light (pastel) space, hover the Gmail favorite: the card is
  light and frosted with dark text and a light ＋; on a dark space Arc's dark card.
- **URL dropdown from the floating sidebar:** hide the sidebar (⌘S), bring it out at the edge, click
  its URL field and type: the sidebar stays out while the dropdown is open, and the dropdown sits
  above it, nothing typed cut off; Escape or Return: the sidebar goes again once the pointer leaves.
- **Extensions popover and Peek:** the popover's top row has Share, Boost (wand) for a web page, the
  star, camera and capture, all square tiles with one corner radius; no Copy Link. Right-click a
  link: "Open Link in Peek (⇧-Click)" after Little Window opens it in Peek.
- **Small fixes:**
  An unloaded chrome://history tab: its globe sits exactly in the middle of the dashed ring.
  A download's thumbnail at the Library button leaves 5 s after it lands (shrinking as it fades),
  not while you hover the button or the list. Switching spaces closes an open theme picker. A new
  space starts a little see-through (the desktop frosted through it).
- **Command bar look:** ⌘T: the bar has the reference's look: near-black at 80 % over a thin material
  (light: #F8F8F8), a dark hairline rim with a light line inside it, a hairline under the field 12 pt
  in, 13 pt medium rows (titles light grey, details at 42 %), "Tab" keycaps on a faint tile; keys,
  arrows and the bounce behave as before.
- **Popovers go with what they hang from:** open the Extensions popover (and, separately, the bookmark
  card) from the floating sidebar: the sidebar stays out while it is open, the pointer can go into it;
  hide the sidebar (⌘S, or the Library's ⇧⌘L): the popover goes as the sidebar starts to slide.
  With either popover open, switch spaces (⌃2, the dock, a swipe): it goes at once.
- **Folder colours:** right-click a pinned folder ▸ Icon Color: Auto, White, Black, then ten
  colours. Pick Red: the folder glyph is red (front), with a dark red outline, open and closed, on a
  light and a dark theme; Auto brings the theme's back; White after Red replaces it. A bookmark
  folder's Icon Color does the same in the Library, and in the bookmark card's folder menu.
- **Library hover:** open View Library (from the button, ⇧⌘L, and from the floating sidebar) and
  don't move the pointer: no rail button (Archived Tabs included) and no row is lit unless the
  pointer is really on it. Hide the floating sidebar with the Library open and bring it back: nothing
  is lit.
- **Floating sidebar with the Library:** hide the sidebar (⌘S), reveal it from the edge, open View
  Library, move the pointer off the sidebar: it slides away; reveal it again: the space's tabs, not
  the Library. ⇧⌘L with the pointer over the page: the Library comes out and stays until the pointer
  has been on it.
- **Library drawers:** Media, Downloads, Easels, Boosts and Archived Tabs (and the Spaces page)
  slide the sidebar out as a drawer, to about 400 pt (45 % of a narrow window): with the sidebar
  docked the page card slides right with the drawer's edge at its own size (its right part runs out
  past the window's edge), never resized or covered; the page inside doesn't reflow. Closing slides
  it back. ⇧⌘L with the Library open: the drawer closes over the Library (no tab list sliding in
  beside it first) and the space's tabs are there as it lands. With the sidebar hidden, the Library
  in the floating sidebar and the pointer over the page: ⇧⌘L slides the floating sidebar away at
  the Library's width in one motion (it never narrows first); reveal it again: the space's tabs. With the sidebar hidden (or
  floating), the Library opens in the floating sidebar at that width; Escape, the Library button
  or a swipe out leave the sidebar hidden again (floating while the pointer is still on it), never
  docked. After clicking View Library and moving the pointer away, the button isn't left lit. The
  Library's ← (and Escape) slide back to the space on the same spring as a two-finger swipe out.
  ⌘Y opens the history page (chrome://history); View Archive… opens the archive drawer.

- **PR #268, ⌘T:** next to Arc on a themed space and on a default one: the selected row is the
  space's colour (gold on a gold space), white text and a white arrow tile; the info badge takes the
  space's darkest tone. Recent open tabs show "Switch to Tab" before typing. Arrow through results
  and check every row's inks follow the selection; long titles truncate before the trailing action.

- **PR #324, 5-Second Previews:** with Apple Intelligence on and Settings ▸ Max ▸ 5-Second Previews
  on, rest 1 s on a story title on Hacker News, a Google result and a link in a post on X: a loading
  card hangs under the link, then the answer streams in (picture, bold line, 2–4 rows), next to Arc's
  on the same link (arc-reverse-engineering.md has its measurements). A story's "comments" link, a
  Google side-panel link and a plain hover on any other site show nothing; Shift held as the pointer
  reaches a link shows the answer, or the small card for a link within the site. Leaving the link
  closes it at once unless the pointer is on the card. Share ▸ Copy as Text and Copy as Image paste as
  Arc's do. Check a beige and a dark space, 1x and 2x.
- **Music notes:** on a release build, play a favorite on YouTube Music, SoundCloud or Spotify
  (the 1x/2x side-by-side with Arc used nts.live and a local tone, 11–12 Nov). Notes rise from the
  icon's top edge, stop 8 pt above the top row and in lower rows drift over the tile above. Pause:
  they go at once, and a quick resume brings them back. Mute and Reduce Motion: they keep floating,
  as Arc's do. A regular YouTube video shows none. By hand: split favorites in both orientations,
  dragging a playing favorite, space swipes and a space with no favorites, for clipping
  regressions. If notes look denser or wider than Arc's, take a minute-long recording of each.

- **#196:** hover a Today tab and move onto its ✕ several times. The ✕ never vanishes before
  the click.
- **#7:** click a tab while moving the pointer a few points on a trackpad. It opens.
- **#3, #208:** a middle click on a sidebar tab row closes it; one in a page never does. ⇧⌘J
  opens Downloads in the sidebar; Esc or the back arrow closes the Library.
- **#233:** with a real mouse, its back button over the sidebar goes to the previous space and
  forward to the next, docked and in the hidden sidebar (⌘S); over a page they still go back and
  forward in the tab's history. A mouse that emits button 3/4 does this on mouse-up. An MX Master
  with Logi Options+ does not: set Back/Forward to the keystrokes ⌥← and ⌥→ (a plain shortcut, not
  the smart Back gesture) on the Cra profile. Console should log `Cra: mouse key back:`. The
  scenario never sees a real button or that key, so only this check proves the monitor does.
  With Options+'s own Back and Forward assignments (the gesture, an MX Ergo's default) the same
  holds: Console logs `Cra: mouse swipe back:`. In Split View the pane under the pointer goes back,
  not the focused one, and a tab a link opened closes back to its opener. A test can't make a swipe
  event, so only this check proves the swipe monitor.
- **#260:** on a built-in trackpad, every space change by a two-finger swipe over the sidebar
  ticks once: a short flick, a slow drag past half (the tick comes at half), and a swipe into
  the Library and back out. A short drag that settles back is silent; a sideways wheel never
  ticks (Arc). `PageDetentHaptics` holds the rule; only a finger feels the tick.
- **#12:** a two-finger swipe in the hidden sidebar (⌘S) switches spaces, and the next space
  draws mid-swipe. There is one link bubble only, and the dashed ring shows only on a
  cross-space keyboard switch.
- **#28:** the speaker sits between favicon and title, a click mutes, and it doesn't blink
  between tracks.
- **#47:** ⌘T highlights the New Tab row; the list scrolls only enough to show the active row.
- **#85:** ⌘Return keeps the bar open; the "New Tab Created" toast shows only while the sidebar
  is hidden.
- **#92:** in a Little Window, ⌃⌘2 sends the page to the window already on space 2.
- **#174:** with a page text field focused, ⌘Space switches input source and ⌘` switches
  windows.
- **#194:** in Google Docs, ⇧⌘C copies the URL instead of opening Word count; DevTools still
  gets ⇧⌘C.
- **#192:** in a page's rich text field, ⇧⌘V pastes plain text and Edit ▸ Paste and Match Style
  is enabled.
- **#33:** hover the player stack: check the volume slider, the Picture in Picture button, and
  the light card in a light space.

### Peek, Little Window, Picture in Picture, split view, Capture

- **Peek from a page without a link under the pointer** (Gmail: open a message's link that opens a
  window from script): the card grows out of the click, small to large, into its place, and closes
  back into it (cra.log: "peek: from the click").

- **PR #221:** opening a Peek fades the page behind and draws it back a little, its margins widening
  while the sidebar stays still, and closing brings it back in one smooth motion with no jump at the
  end. With "Pages fill the window edge to edge" on, the page only fades. (The values are checked
  by the peek-backdrop scenario; this is the motion.)
- **#195:** in a Peek and a Little Window, click in the page, then Back, Forward, Refresh, the
  address and "Open in": each works on the first click. Capture and scroll: the page moves and
  the grey picture and the lens follow. With another app full screen, ⌥⌘N opens a Little
  Window over it, and doesn't when Settings ▸ Tabs ▸ Links is off.
- **#357:** play an embedded YouTube video aloud on a blog (the player in an iframe), switch tabs:
  it goes into Picture in Picture. A background test copy can't hand the iframe its key press,
  before or after #357; the pip-leave-tab scenario covers a player in the page itself.
- **#357:** on crabrowser.app/folder with a 4-tab folder, Open All opens one tab and the toolbar's
  crossed-out windows button (or "Pop-ups Blocked" under the sidebar's address) shows; its menu
  opens the rest, and Always Allow Pop-ups from crabrowser.app lets the next Open All open all.
- **#202:** in a Peek, ⌘-click a `target=_blank` link: a background tab opens and the Peek
  stays. A plain click on it takes the Peek away and selects the new tab below the source tab.
- **#242:** Peek a link from a pinned tab, scroll the Peek, click a `target=_blank` link in it: the
  new tab shows with no Peek and the pinned row keeps the peeked page's favicon. Click the pinned
  row: the same Peek is back at the same scroll, the page behind faded, and clicks in it work.
  With the Peek shown, click another tab's row: that tab opens (the Peek waits); a click on the
  faded page beside the card closes it. (Which Peek shows when is the peek-per-tab scenario;
  this is the look, the scroll and the real clicks.)
- **PR #222:** with a Peek open, the browser window keeps its full shadow and coloured traffic
  lights, also after a click in the Peek, as in Arc. A drag from every edge and corner resizes the
  window with the Peek open and the card follows; a click on the background 4 pt or more inside
  the window closes it.
- **#186:** send a link from a full-screen app. The Little Window opens centred on that Space
  with no switch to the desktop, and a video in it can still go full screen.
- **#354:** on two displays, with another app full screen on the primary one and Cra on the
  other: a link that opens a tab, a ⌘-click that opens one behind, a tab whose page has to load,
  a Peek and DevTools all leave the primary display on its full-screen Space.
- **#231:** with Keep Cra in the menu bar on, the C shows in the menu bar in light and dark.
  ⌘Q takes the windows and the Dock icon away, and focus goes to the app behind. A full-screen
  window leaves its Space first. ⌥⌘N from another app opens a Little Window at once, with the
  Dock icon. Closing it takes the icon away again. New Window in the item's menu brings the
  windows back, and Quit Cra there quits.
- **#319:** with a custom app icon and Keep Cra in the menu bar on, ⌘Q, then New Window from the
  item's menu: ⌘-Tab and the Dock show the custom icon, not Segments
  (app-icon-dock-return.scenario only sees that Cra set it again). Then download a file: during
  and after the download, ⌘-Tab and the Dock still show the custom icon, with Chromium's progress
  badge on it while it runs (app-icon-download.scenario reads what Cra draws, not what the Dock shows).
- **#298:** in a tab on a DRM service (it opens in WebKit, docs/protected-media.md), Option-click a
  link: it opens as a split pane beside the page, as it does in any other tab (that scenario's
  posted click never reaches a WebKit page behind other windows).
- **#172:** with a space on its own profile, a Little Window from that space and a Peek from its
  tab see that profile's cookies. The chip names the profile; switching it reloads the page in
  the other profile.
- **#329:** a Little Window's strip is a gradient, deep blue-grey at the left to purple-grey at the
  right, in every space (compare Arc 1.172.1 beside it). Its traffic lights are grey with the window
  in front and the pointer elsewhere, and red, yellow and green with glyphs while the pointer is over
  them. The address pill is a lighter wash over the strip, also under the pointer.
- **#330:** the address pill reads the host only (no port, path or query). An http page shows an
  orange open padlock on a pale orange tile where the magnifier is; an https page and a blank one
  show the magnifier, and so does a window still waiting for its first response.
- **#206:** a video's PiP and Meet's PiP stay on top over a full-screen app, and clicking or
  dragging them doesn't bring Cra forward.
- **#198:** in a Meet call with automatic picture-in-picture on, leaving the tab opens Meet's
  PiP and coming back closes it. The tab shows the recording dot and doesn't sleep.
- **#134:** with another app in front, the PiP edges show resize cursors, and a click on play
  doesn't move the window.
- **#246:** a YouTube video's PiP shows no Chrome strip (site icon, host, dark top band) at any
  point, also in the first seconds; with the pointer away it is the bare video. On hover: Back to
  Tab on the left (with its words from 400 pt wide), the host centred and whole, Close on the
  right, one even dim layer.
- **#262:** hover a YouTube PiP after a drag on its edges, a resize, a trip to another app's
  full-screen Space and back, and a click on Cra's window: only Cra's controls show (no grey ±10,
  no second ✕, no scrubber). Play/pause alone in a window under 280 pt wide, with the ±15 pair
  and a bigger play/pause from 280 pt; `cra.log` has no "Chromium's window became key".
- **#178:** in a split, the focused pane's ring shows (also over docked DevTools), and so does
  the card shadow.
- **#90:** Capture on a second display and behind other windows isn't blank. It goes to the
  clipboard with the "Screenshot Copied to Clipboard" toast, and Save offers Downloads.
  Full-page capture shows "Capture in Progress" first. Share keeps the control center open. On
  an https page with a certificate error the lock reads "Not Secure" and opens the certificate
  sheet.

### Extensions and developer mode

- **#203:** import a store extension from Arc, open a page, then reload the extension in
  `chrome://extensions`: it stays on and shows as from the Web Store. "Add to Chrome" puts
  nothing in `~/Downloads` and shows no save panel.
- **#43:** Load unpacked in `chrome://extensions`. The extension shows in the open Extensions
  popover within about 1 s, and so does an on/off switch.
- **#41:** on a test copy, `Extensions.triggerAction` on a turned-off extension answers "No
  enabled extension…" instead of crashing.
- **#8:** a Bitwarden popup opens in under 0.5 s and hangs from the button's right edge. A
  dragged popup reopens at the same offset after the window moves.
- With Cra in native full screen and Bitwarden locked, open its separate vault-unlock window:
  it appears over Cra on the same macOS Space, accepts the password and closes normally without
  switching to a desktop. Compare with Arc; also check windowed Cra and a second display.
- **#38:** in full screen, SwitchyOmega's Options doesn't slide the Space away, and a second
  click selects the open options tab.
- **#42:** clicking the URL in the developer bar edits it in place with the whole URL selected
  (Return loads, Esc cancels). A long press on the Extensions button doesn't close and reopen
  the popover.
- **#9:** for a pinned extension, Monochrome, Symbol, Choose Image… and Original Icon each work
  and survive a restart.
- **#89:** in developer mode the ⌄ chevron lists Refresh ⌘R, Force Refresh ⇧⌘R, Clear Cookies
  and Refresh, Clear Cache and Refresh, View Source ⌥⌘U and Developer Tools ⌥⌘I. Tab row
  context menus show their shortcuts.
- **#265:** signed in to a paid Claude plan, Claude in Chrome's toolbar button opens its panel
  and Claude works in it: no "Claude isn't available on this page" and no "Can't reach Claude
  in Chrome". The scenario covers what the extension checks, but only an account gets past
  claude.ai's sign-in.

### Profiles, privacy, media and the engine

- **#111:** reset Cra's camera access (`tccutil reset Camera <bundle id>`), open Meet, click "Use
  microphone and camera" and Allow. One Cra prompt shows, then macOS's own dialog, and nothing
  crashes.
- **#36:** on a new data folder, finish onboarding with an Arc import that brings extensions and
  passwords, so Cra relaunches. The quitting process leaves no crash report.
- **#5:** with Cra running, `ps -axo args | grep 'Cra Helper'`: the renderer, GPU, network,
  storage and audio helpers carry `--seatbelt-client`; only video capture runs without it.
- **#66:** signed in, a Disney+ title and a Prime Video title both play, in Safari's engine.
- **#167:** on a Mac whose first language is Simplified Chinese, cra.log says `chromium locale:
  zh-CN` and chrome://version shows `--lang=zh-CN`.
- **#133:** pick Google in Settings ▸ Privacy ▸ Secure DNS. Without a relaunch, cra.log says
  `secure dns: secure via dns.google` and chrome://settings/security shows the same choice.
- **#190:** with Ask Where to Save Each File on, the save panel is a sheet on Cra's window, and
  Cancel cancels the download.
- **#272:** download a large file. The bin over the Library button keeps a ring that fills as it
  downloads; right-clicking its row in the tray and on Library ▸ Downloads offers Pause Download and
  Cancel Download, and a paused row reads "Paused". ⌘Q while it runs asks "Downloads in progress";
  Keep browsing keeps it going. Once it finishes, a check replaces the arrow, and its row's menu
  reads Open / Copy <kind>, Show in Finder, Hide from Cra and Move to Trash.
- **PR #254:** with the release app as the default browser, open a page in Safari on an iPhone
  signed in to the same Apple Account and click the Handoff icon in the Dock. The page opens in
  Cra, in the space Air Traffic Control picks, and not in Safari.
- **#261, #195:** with Stage Manager on, use Cra full screen with 20 or more visited tabs for ten
  minutes. No grey pane flashes and Stage Manager shows no window coming and going. After a
  minute pass, the GPU helper's footprint (`footprint -p <pid>`) still drops as the hidden tabs
  let go of their tiles (#195: 20 tabs, 386 → about 235 MB).

### Sync

- **PR #289:** with a signed build on two Macs and Sync with iCloud on, a tab opened on one Mac
  shows on the other within about a minute, and back, five times in a row. Settings ▸ General
  shows "Synced" on both and never asks which sidebar to keep after the first answer. Needs
  real iCloud: the harness only stands in for a file that is still downloading.
- **PR #289:** the same with a folder in Dropbox, OneDrive or a similar service instead of iCloud.

## Not pinned yet

Each of these needs a change to production code before a test can pin it: a move into
CraCore (rule 1 in CLAUDE.md), or a `cra://debug` hook a scenario can read. Do the one for an
issue when a change touches that code anyway.

| Issue | What would let a test pin it |
|---|---|
| #202 | Move where a link's tab lands (`BrowserManager.openLinkTab`) into CraCore, e.g. a `LinkTabPlacement` value |
| #172 | Move the Little Window's profile order (opener's page, Peek's tab, target space) out of `LittleWindowController.init`; or a `littleProfile` hook logging its profile folder |
| #186 | `cra://open?…&little=1` honours `CRA_TEST_BACKGROUND`, and `debug?windows=1` logs `collectionBehavior` |
| #178 | Split panes keep their bars with the toolbar hidden (`ShellView.barsShown`), and View ▸ Show Toolbar is disabled in a split: both in files no harness compiles |
| #191 | Move the drop-target rule (a tab over a row's middle splits, never into a folder) out of `SpaceListView` |
| #47 | Move `SpaceListView.revealActiveRow` (scroll the least that shows the row) |
| #139 | Move `navigatedAway` (pinned, URL differs from the saved one) out of `SpaceListView` |
| #3 #21 #86 #195 | Default bindings (⇧⌘J, ⌃⌘1–9, ⇧⌘T, ⌥⌘N) live in `App/KeyBindings.swift`, a known exception |
| #194 | `AppDelegate.reservedActions` must hold `copyURL` and `copyURLMarkdown`: a `reserved=<action>` hook or a move |
| #192 | A `validate=pasteAsPlainText` hook logging whether the item is enabled while a page has focus |
| #21 | An `undoKey` hook logging whether ⌘Z undoes typing or reopens a tab |
| #49 | `SuggestionEngine` (at most five rows, never the current tab), a known exception |
| #171 | `themeShown` also logs the window's appearance and effective appearance (menus and sheets follow it) |
| #187 | `themeShown` also logs the command bar's appearance and highlight colour |
| #152 | `spaceTip=<n>` logs the tip's text, profile pill and caps |
| #40 #170 | `spaceMenu=1` logs the space header menu's items in order, and the list's right-click menu too |
| #132 #156 | A `windowActive=0\|1` override, since a background scenario window is always "blur, active" |
| #22 | Move `ExtensionStore.Entry.isInstalled` and `isEnabled(inProfile:)` into CraCore |
| #106 | Move the action icon fallback (`default_icon` as a dict or string, else `icons`) into CraCore |
| #9 | Move `IconStyle` into CraCore with a fixture; or `pinExtension` and `extensionIconStyle` hooks plus a toolbar snapshot |
| #89 | A `menuItemsAt=x,y` hook logging each item's title and shortcut |
| #8 | Move `ExtensionPopupWindow.placement(anchor:width:)` and the drag offset into CraCore |
| #137 | A cra.log line when the permission sheet shows (`permission sheet <host>: <kinds> (tab\|little)`), so a scenario can show a Little Window asks for notifications |
| #5 | A `processes` hook logging each helper's `--type=` and whether it runs under the sandbox |
