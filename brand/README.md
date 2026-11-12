# Pane brand marks

Pane (pane.uz) is a fork of Cra, rebranded on 12 Nov 2026. The mark is three frosted window
panes overlapping down and to the right, the front one a browser window with a sidebar, on a
squircle tile with Apple's continuous corners. No letters.

| File | Use |
|---|---|
| `pane-icon.svg` | App icon (Arctic): the panes on the tile, with the orb their frost blurs. Source for the macOS `.icns`. |
| `pane-mark-mono.svg` | Single colour, inherits `currentColor`: the panes alone, the front one filled. |

## Icons

`scripts/make-app-icons.swift` writes these files and every app icon from code (no hand-drawn
art): the SVG is built from a palette, then WebKit renders it onto Apple's 824/1024 grid.

| Icon | Tile | Orb |
|---|---|---|
| Arctic (bundled) | `#7fd3ff` to `#1f4fd1` | `#f2fdff` to `#47d6ff` |
| Midnight | `#2b3560` to `#070a18` | `#c3b4ff` to `#5a3df0` |
| Frost | `#f6f9fd` to `#b8cbe2` | `#ffffff` to `#8fb7e8` |
| Rose | `#ffc77e` to `#d93a78` | `#fff6c9` to `#ff9a3d` |
| Graphite | `#9aa1ab` to `#24272d` | `#ffffff` to `#aeb7c3` |

Each pane's frost is the scene behind it blurred (22 of 1024) and clipped to the pane, then a
white milk (more on the front pane), a diagonal gloss and a white rim. Change a palette in the
script and run it again; lint's `app-icon-grid` rule checks the results.
