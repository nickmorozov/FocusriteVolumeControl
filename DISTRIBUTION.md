# Distribution Guide

## Why Not the Mac App Store

This app **cannot** be distributed on the Mac App Store because it requires:

1. **`CGEventTap`** — intercepting media keys needs Accessibility permission, which sandboxed apps cannot use
2. **`osascript` subprocess** — controlling Focusrite Control 2 via Apple Events is blocked in the sandbox

The project has `ENABLE_APP_SANDBOX = NO`. The App Store requires sandboxing with no exception. Apps like BetterTouchTool, Karabiner, Alfred, and Bartender all distribute outside the App Store for exactly this reason.

## Direct Distribution

### Step 1 — Apple Developer Program

- Enroll at <https://developer.apple.com/programs/> ($99/year)
- Create a **Developer ID Application** signing certificate (not "Apple Development")
- This is required for notarization, which is required for macOS to allow users to open the app

### Step 2 — Notarize the App

Apple requires notarization for apps distributed outside the store. Without it, macOS shows a scary "unidentified developer" warning.

```bash
# Archive with Developer ID certificate
xcodebuild archive \
  -scheme FocusriteVolumeControl \
  -configuration Release \
  -archivePath ./build/FocusriteVolumeControl.xcarchive \
  CODE_SIGN_IDENTITY="Developer ID Application"

# Export the archive
xcodebuild -exportArchive \
  -archivePath ./build/FocusriteVolumeControl.xcarchive \
  -exportPath ./build/export \
  -exportOptionsPlist ExportOptions.plist

# Submit for notarization
xcrun notarytool submit ./build/export/FocusriteVolumeControl.app.zip \
  --apple-id your@email.com \
  --team-id YOUR_TEAM_ID \
  --password app-specific-password \
  --wait

# Staple the notarization ticket to the app
xcrun stapler staple ./build/export/FocusriteVolumeControl.app
```

### Step 3 — Payment + Licensing

For a one-time purchase with a free trial (no subscription):

| Service | Trial Support | Cut | Notes |
|---------|:---:|:---:|-------|
| **Paddle** | Built-in | 5-10% | Most popular for Mac indie apps |
| **LemonSqueezy** | Built-in | 5% + 50c | Simpler, newer |
| **Gumroad** | Manual | 10% | Simplest to set up |

**Paddle** is the most common choice for indie Mac apps. It provides:
- License key generation and verification
- Built-in trial period (configurable, e.g. 7 days)
- Payment processing and tax handling
- macOS SDK to embed in the app for license checks

### Step 4 — Implement Trial Logic

With Paddle SDK (or similar), the app launch flow becomes:

```
App Launch
    -> Check license
    -> If valid -> full access
    -> If no license -> check trial start date
        -> If within 7 days -> full access + "X days left" badge
        -> If expired -> show purchase prompt, disable functionality
```

Store the trial start date in Keychain for tamper resistance (UserDefaults is too easy to reset).

### Step 5 — Package as DMG

Create a `.dmg` with a drag-to-Applications installer:

```bash
# Create a temporary DMG folder
mkdir -p ./build/dmg
cp -R ./build/export/FocusriteVolumeControl.app ./build/dmg/
ln -s /Applications ./build/dmg/Applications

# Create DMG
hdiutil create -volname "FocusriteVolumeControl" \
  -srcfolder ./build/dmg \
  -ov -format UDZO \
  ./build/FocusriteVolumeControl.dmg

# Notarize the DMG too
xcrun notarytool submit ./build/FocusriteVolumeControl.dmg \
  --apple-id your@email.com \
  --team-id YOUR_TEAM_ID \
  --password app-specific-password \
  --wait
xcrun stapler staple ./build/FocusriteVolumeControl.dmg
```

### Step 6 — Distribution

- Create a landing page (GitHub Pages, simple static site, or the payment service provides one)
- Host the DMG download (GitHub Releases, your own site, or the payment service hosts it)
- Paddle/LemonSqueezy can handle the full checkout + download flow

## Pricing

Similar single-purpose Mac utilities typically charge **$5-15** one-time. For a niche Focusrite tool, **$5-8** is reasonable.

## Future Subscription Features

If you add major features later (e.g. direct AES70/OCA protocol support, multi-device control, EQ profiles), those can be offered as a separate subscription tier while keeping the base one-time purchase.
