# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-file macOS utility (`glow.swift`) that boosts XDR/HDR display brightness by rendering a Metal overlay with `multiplyBlendMode` and a clear color value > 1.0. Requires a display with EDR support (MacBook Pro Liquid Retina XDR or Pro Display XDR).

## Running

```bash
swift glow.swift [brightness]    # brightness: 1.0-3.0, default 1.5
```

No build step, no dependencies, no package manager - uses only macOS native frameworks.

## Architecture

Everything lives in `glow.swift` (~175 lines):

1. **Startup** (lines 19-39): parses brightness arg, validates EDR support via `screen.maximumPotentialExtendedDynamicRangeColorComponentValue`
2. **EDRView** (lines 45-135): NSView subclass with a `CAMetalLayer` configured for RGBA16Float + Extended Linear Display P3. A 1-second timer calls `render()` to keep EDR engaged. Sets `compositingFilter = "multiplyBlendMode"` so the overlay multiplies underlying pixels by the brightness value.
3. **Overlay window** (lines 137-156): borderless, click-through, `.screenSaver` level window covering the full screen
4. **Status bar menu** (lines 158-170): shows current brightness %, quit button

The core trick: Metal clear color set to `(v, v, v, 1.0)` where `v > 1.0` in extended linear P3 space. Multiply blend mode makes each screen pixel brighter proportionally.
