# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Build
xcodebuild -scheme FocusriteVolumeControl -configuration Debug build

# Run all tests
xcodebuild test -scheme FocusriteVolumeControl -configuration Debug

# Run a single test class
xcodebuild test -scheme FocusriteVolumeControl -configuration Debug -only-testing:FocusriteVolumeControlTests/VolumeControllerTests

# Run a single test method
xcodebuild test -scheme FocusriteVolumeControl -configuration Debug -only-testing:FocusriteVolumeControlTests/VolumeControllerTests/testVolumeUp
```

There is one scheme (`FocusriteVolumeControl`) and two targets: the app and `FocusriteVolumeControlTests`. No external dependencies — pure Apple frameworks only (SwiftUI, Combine, AppKit, ServiceManagement).

```bash
# Release: build and install to /Applications
xcodebuild -scheme FocusriteVolumeControl -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/FocusriteVolumeControl-*/Build/Products/Release/FocusriteVolumeControl.app /Applications/
xattr -cr /Applications/FocusriteVolumeControl.app
```

Note: After replacing the binary in `/Applications`, the user may need to re-grant Accessibility permission in System Settings and relaunch the app.

## Architecture

This is a **macOS menu bar app** that controls a Focusrite Scarlett Solo's volume by driving the Focusrite Control 2 (FC2) application via UI automation. It intercepts system media keys so hardware volume buttons control the Focusrite instead of the Mac's built-in audio.

### Core Data Flow

```
Media Keys / Hotkeys / UI
        ↓
  VolumeController          ← central state manager, @Published properties
        ↓
  VolumeBackend (protocol)  ← pluggable backend abstraction
        ↓
  AppleScriptBackend        ← current: drives FC2 via osascript subprocess
  FCServerBackend           ← placeholder: future direct AES70/OCA protocol
```

**VolumeController** (`VolumeController.swift`) is the hub — it owns the backend, manages all state (`playbackVolume`, `playbackMuted`, input volumes, `directMonitorEnabled`, `isConnected`), and exposes `@Published` properties that SwiftUI views observe.

**VolumeBackend** (`VolumeBackend.swift`) is the protocol. Backends publish state via a Combine `statePublisher`. The controller subscribes and propagates changes. Backends can be switched at runtime via `switchBackend(to:)`.

**AppleScriptBackend** (`AppleScriptBackend.swift`) is the active implementation. It shells out to `osascript` to read/write FC2 slider values, toggle mutes, and control the Direct Monitor checkbox. It also handles FC2 launch, window discovery, and minimization.

### Media Key Interception

**AppDelegate** installs a `CGEventTap` to intercept `NX_KEYTYPE_SOUND_UP` (0), `NX_KEYTYPE_SOUND_DOWN` (1), and `NX_KEYTYPE_MUTE` (7). The tap blocks these events from reaching macOS and routes them to VolumeController instead. Requires Accessibility permission.

### Custom Hotkeys

**ShortcutManager** (singleton) persists shortcuts as JSON in UserDefaults. **HotkeyManager** registers `NSEvent` global/local monitors that match keyCode + modifiers and dispatch to VolumeController actions.

### Perceptual Volume Curve

Volume is stored in dB (-127 to 0, or -127 to +6 with gain enabled). UI sliders use a perceptual curve with exponent `0.197` so that 50% slider position = -16 dB. The conversion functions live in VolumeController (`dBToPercentage` / `percentageToDB`).

### Volume HUD

A custom floating HUD (`VolumeHUDWindow.swift` + `VolumeHUDView.swift`) replaces the macOS system volume popup. Media key events return `nil` from the CGEventTap to suppress the system HUD entirely.

- **VolumeHUDWindow** — `NSPanel` subclass: borderless, non-activating, click-through, floats above all windows including fullscreen (`.screenSaver` level)
- **VolumeHUDPanel** — singleton manager with `show()` (displays panel, resets 2s dismiss timer) and `update()` (refreshes values without showing). Fades in (0.15s) and out (0.3s).
- **VolumeHUDView** — SwiftUI horizontal capsule: speaker icon, perceptual fill bar (same curve as VolumeController), dB label. Overgain shows orange fill past a 0 dB tick mark.
- **HUD trigger logic**: `show()` is called explicitly from media key and hotkey handlers. `update()` is called from a Combine subscription to keep values fresh. This means the HUD appears for key/hotkey presses but NOT for slider drags in the popover.

### UI Layer

- **PopoverView** — menu bar popover (volume slider, mute, input controls)
- **PreferencesView** — settings window (general options, backend picker, shortcut editor)
- **ShortcutRecorderView** — NSViewRepresentable bridge for capturing raw key events

### Testing

Tests use **MockVolumeBackend** (`MockVolumeBackend.swift`) which records all calls and allows configurable responses. Tests are `@MainActor async` and use a `waitForStateUpdate()` helper for Combine propagation. No real FC2 connection needed.

## Key Conventions

- All volume values are in **dB** internally. UI percentage conversion happens at the view/controller boundary.
- Backend state flows unidirectionally: backend → `stateSubject` → `statePublisher` → VolumeController `@Published` → SwiftUI views.
- The `VolumeBackend` protocol must be conformed to for any new backend. See `FCServerBackend.swift` for the stub template.
- `FocusriteClient.swift` is an experimental TCP client for future direct protocol support — not integrated into the app.
