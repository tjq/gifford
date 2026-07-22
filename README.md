# Gifford

A tiny macOS **menu bar** app that turns screen recordings (`.mov` / `.mp4`) into GIFs.
No Dock icon, no window — it lives in the menu bar.

## What it does

Click the menu bar icon → **Convert Recording(s) to GIF…** → pick one or more
recordings → each is converted with a two-pass palette filter (`palettegen` +
`paletteuse`) for clean colors and crisp text, then revealed in Finder.

## Settings

Everything is configurable from the menu and persisted across launches:

- **FPS** — 10 / 15 / 20 / 30
- **Size** — 100% / 75% / 50% / 33% of the original resolution
- **Quality** — High / Medium / Low (palette size + dithering trade-off)
- **Save GIFs** — next to the original, ask each time, or a fixed folder of your choice

Defaults are unchanged from the old fixed behavior: **15 fps, native size, high
quality, saved next to the original**.

## Requirements

- **ffmpeg** — `brew install ffmpeg` (the app finds it in `/opt/homebrew/bin`,
  `/usr/local/bin`, or your login-shell `PATH`)
- macOS 11+ and the Xcode Command Line Tools (`xcode-select --install`) to build

## Install with Homebrew

```sh
brew install --cask tjq/tap/gifford
```

ffmpeg is installed automatically as a dependency.

## Build & install

```sh
./build.sh --run
```

This compiles `main.swift`, assembles `Gifford.app`, installs it to
`~/Applications`, and launches it. Re-run any time you edit the source.

## Keep it in the menu bar

Add it to **Login Items** so it's always there:

System Settings → General → Login Items → **＋** → choose
`~/Applications/Gifford.app`.

## Files

| File         | Purpose                                             |
|--------------|-----------------------------------------------------|
| `main.swift` | The whole app (menu bar item, settings, ffmpeg)     |
| `Info.plist` | Bundle metadata (`LSUIElement` = menu-bar-only app) |
| `build.sh`   | Compile → bundle → ad-hoc sign → install            |

## First launch

Because the app isn't notarized, the **first** time you may need to allow it via
System Settings → Privacy & Security. macOS will also ask permission the first time
it reads files from Desktop/Downloads — that's expected.
