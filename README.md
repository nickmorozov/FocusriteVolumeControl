# Focusrite Volume Control

A macOS menu bar app that lets you control your Focusrite Scarlett Solo volume with your keyboard's media keys and custom shortcuts.

## Install

### Homebrew

```bash
brew tap enum-solutions-inc/focusrite-volume-control
brew install --cask focusrite-volume-control
```

### Manual

Download the latest DMG from [Releases](https://github.com/enum-solutions-inc/focusrite-volume-control/releases/latest) and drag to Applications.

## Requirements

- macOS 15.0 (Sequoia) or later
- [Focusrite Control 2](https://focusrite.com/downloads) installed
- Accessibility permission (prompted on first launch)

## Features

- **Media key interception** — volume up/down/mute keys control your Focusrite instead of built-in speakers
- **Custom HUD** — floating volume overlay showing actual dB level
- **Perceptual volume curve** — 50% slider = -16 dB, matching how your ears perceive loudness
- **Custom hotkeys** — assign any keyboard shortcut to volume, mute, and direct monitor
- **Auto-detect** — activates only when a Focusrite Scarlett is the default output device
- **Direct monitor toggle** — control direct monitoring without opening Focusrite Control 2

## How it works

The app drives Focusrite Control 2 via UI automation (AppleScript + Accessibility API). It intercepts system media keys through a `CGEventTap` and routes them to FC2's sliders instead of macOS's built-in volume control.

## Build from source

```bash
xcodebuild -scheme "Focusrite Volume Control" -configuration Release \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

## License

MIT
