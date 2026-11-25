# SpaceTag

Give each macOS Space (desktop) a name. The name shows:

- in Mission Control (four-finger swipe up), on top of the "Desktop N" caption
- in the menu bar, for the Space you are on
- in the middle of the screen for a moment after you switch Spaces (can be turned off)

## Build and install

```sh
./build.sh install     # builds, copies to ~/Applications, launches
```

Then allow it in **System Settings → Privacy & Security → Accessibility**.
The app needs this to read where Mission Control draws each Space.
Without it, the app shows one line with all names under the Spaces bar.

Each build has an ad-hoc signature. macOS ties the Accessibility grant to one build,
so after each `./build.sh install` you must allow it again.

## Use

Click the name in the menu bar → click a Space → type a name (emoji works).
Leave the name empty to remove it.

## How it works

```
 every 150 ms                       while Mission Control is open (every 70 ms)
┌───────────────────────┐  open   ┌────────────────────────────────────────────┐
│ Window list: Dock has │ ──────▶ │ Dock AX tree: mc → mc.display → mc.spaces  │
│ full-screen window at │         │ → mc.spaces.list → one button per Space    │
│ layer 18/20?          │         └────────────────────────────────────────────┘
└───────────────────────┘                          │ button i  ↔  Space i
                                                   ▼ (same order as CGSCopyManagedDisplaySpaces)
                                   ┌────────────────────────────────────────────┐
                                   │ Name pill windows (made at launch, alpha 0)│
                                   │ move over each button's caption, alpha 1   │
                                   └────────────────────────────────────────────┘
```

- Names are saved in `UserDefaults` (`local.spacetag`), keyed by Space UUID.
  They stay with a Space when you reorder Spaces in Mission Control.
- Space data comes from private CoreGraphics calls (`CGSCopyManagedDisplaySpaces`,
  `CGSGetActiveSpace`). A future macOS update can break them.

## Debug

```sh
defaults write local.spacetag debugLog -bool true   # log Spaces bar frames
tail -f ~/Library/Logs/SpaceTag.log
```
