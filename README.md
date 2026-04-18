# Glow 🌟 — Push your XDR display beyond 100% brightness.

[![License: MIT](https://img.shields.io/badge/License-MIT-ffd60a?style=flat-square)](https://opensource.org/licenses/MIT)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-0078d7?logo=apple&logoColor=white&style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-script-F05138?logo=swift&logoColor=white&style=flat-square)](https://swift.org/)
[![Single file](https://img.shields.io/badge/source-single_file-22c55e?style=flat-square)](glow.swift)

Glow renders a Metal overlay with `multiplyBlendMode` to drive EDR displays past their 100% SDR ceiling — up to 3× brightness. Lives in your menu bar. No build step, no dependencies, no Xcode.

## What you get

- Up to **3× SDR brightness** on MacBook Pro Liquid Retina XDR and Pro Display XDR.
- Menu bar presets: 125%, 150%, 175%, 200%, 250%, 300%.
- Pause/resume with `⌘P` — the overlay fades out without closing the app.
- Brightness level **persisted across restarts** — picks up where you left off.
- Runs as a **LaunchAgent** so it starts automatically on login.
- Zero dependencies: Metal + Cocoa + QuartzCore, all built into macOS.

## Requirements

- macOS 14.0 (Sonoma) or later
- A display with EDR support:
  - MacBook Pro with Liquid Retina XDR (14" / 16")
  - Apple Pro Display XDR

Glow exits gracefully on displays without EDR support.

## Install

**Homebrew (recommended):**
```bash
brew install nmwcode/tap/glow
```

**Manual:**
```bash
git clone https://github.com/nmwcode/glow
cd glow
swift glow.swift          # default: 200%
swift glow.swift 1.5      # custom: 150%
```

**Auto-start on login (LaunchAgent, Homebrew install only):**
```bash
cp com.glow.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.glow.plist
```

## Usage

After launch a sun icon appears in the menu bar.

| Action | How |
| --- | --- |
| Change brightness | Click the menu bar icon → pick a preset (125%–300%) |
| Pause overlay | `⌘P` or menu → Pausar |
| Resume overlay | `⌘P` or menu → Activar |
| Quit | Menu → Salir (or `⌘Q`) |

The chosen preset is saved automatically and restored on next launch.

## How it works

macOS EDR (Extended Dynamic Range) lets displays render luminance above the SDR white point. Glow exploits this with a single Metal trick:

1. A borderless, click-through `NSWindow` at `.screenSaver` level covers the full screen.
2. A `CAMetalLayer` configured for `rgba16Float` + Extended Linear Display P3 renders a solid color with a value > 1.0.
3. `compositingFilter = "multiplyBlendMode"` tells Core Animation to multiply every pixel on screen by that value.
4. A `CADisplayLink` keeps the layer rendering in sync with the display refresh rate so no frames go dark.

```
result = screen_pixel × overlay_value
```

At 200%, each pixel is doubled in luminance — the display drives its backlight into EDR headroom.

> EDR screenshots are clamped to SDR white. A screenshot that looks blown out is evidence the overlay is working, not a bug.

## Uninstall

**Homebrew:**
```bash
brew uninstall nmwcode/tap/glow
launchctl unload ~/Library/LaunchAgents/com.glow.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.glow.plist
defaults delete com.glow
```

**Manual:**
```bash
launchctl unload ~/Library/LaunchAgents/com.glow.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.glow.plist
defaults delete com.glow
```

## License

MIT
