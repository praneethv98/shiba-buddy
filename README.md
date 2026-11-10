# Shiba Buddy

A pixel-art Shiba Inu that lives on your Mac's Dock.

- Walks along the Dock, sniffs around, sits and wags
- Finds bones and buries them
- Chases your mouse pointer when it comes within about 10 cm, then settles down
- Hops onto an app icon and naps: breathing, rolling over, kicking, snot bubble

Native Swift/AppKit, no dependencies. Runs as a menu bar app (no Dock icon of its own).

## Install

Double-click **Install Shiba Buddy.command**, or:

```bash
./install.sh
```

This builds the app, copies it to `/Applications` (or `~/Applications`), launches it and turns on Open at Login.
Requires macOS 14+ and the Xcode command line tools (`xcode-select --install`).

## Permissions

The pup works right away. To let it nap on a specific Dock icon, allow **Accessibility** when asked
(menu bar → "Allow naps on Dock icons…"). Without it, the pup estimates where the icons are.

## Menu

Show / pause the puppy, send it to nap on a random icon, Dock icon access, Open at login, Quit.

## Development

```bash
./build.sh                                              # builds ShibaBuddy.app
./ShibaBuddy.app/Contents/MacOS/ShibaBuddy --self-test  # behavior checks
./ShibaBuddy.app/Contents/MacOS/ShibaBuddy --pupsheet out.png  # every pose in one image
```

| File | What it does |
|---|---|
| `pup.swift` | Pup behavior, pose rendering, Dock geometry, window |
| `pupart.swift` | Pixel art and palette |
| `app.swift` | Menu bar item and frame timer |
| `checks.swift` | Self-tests |
| `icon.swift` | App icon, drawn from the pixel art |
| `util.swift` | Small math, color and drawing helpers |

`build.sh` signs with your Apple Development identity if you have one, so macOS remembers the
Accessibility grant across rebuilds; otherwise it signs ad-hoc.
