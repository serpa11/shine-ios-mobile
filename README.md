# Shine for iOS

A native iOS app that runs [Shine](https://shineaimobile.pages.dev/).

It's a `WKWebView` shell around the site - not a rebuild of it. Everything you
see is the real Shine, loaded from the network, so it stays in step with the web
version automatically. The app's job is to supply the things a browser tab can't:
a real icon on the home screen, native attachment pickers, working downloads, a
share sheet, and pull-to-refresh.

## There is no `.ipa` in this repo

That is deliberate. An iOS app needs an arm64 binary compiled by Xcode and a
signature issued by Apple. Neither can be produced on Windows or Linux, and a
prebuilt `.ipa` in the repo would be either unsigned (uninstallable) or someone
else's code wearing the Shine name. So the repo carries the source and a script
that emits a signed IPA on a Mac.

## Requirements

- macOS with Xcode 15 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple ID. A free one is enough to run on your own device for 7 days; a paid
  Apple Developer account ($99/year) is needed for TestFlight or the App Store.

## Build it

```bash
DEVELOPMENT_TEAM=ABCDE12345 ./scripts/build-ipa.sh
```

Your Team ID is under Xcode > Settings > Accounts, or at
<https://developer.apple.com/account> -> Membership.

The IPA lands in `build/ipa/`. To put it on an iPhone, open
`build/ipa/Shine.ipa` in Xcode's Devices window, or run it through AltStore /
Sideloadly, which re-sign it with your own Apple ID.

Other methods:

```bash
METHOD=ad-hoc     ./scripts/build-ipa.sh   # install on any device, no store account
METHOD=app-store  ./scripts/build-ipa.sh   # for TestFlight / App Store Connect
```

The first `-allowProvisioningUpdates` build needs network access to Apple's
developer portal and will create the App ID and provisioning profile for you.

### No Mac at all

The included workflow builds on a cloud Mac, so you never need one:

```bash
git remote add origin git@github.com:<you>/shine-ios.git
git push -u origin main
```

Then Actions -> Build IPA -> Run workflow, and download `Shine-unsigned-ipa`
from the run summary.

That artifact is **unsigned**, because Apple will not sign without a Team ID.
It still installs, via re-signing with your own Apple ID:

- **Sideloadly** (Windows/Mac) - drag the IPA in, sign in with a free Apple ID,
  done. No developer membership needed.
- **AltStore** - sideload from the IPA in its own UI.

Free Apple IDs give 7-day profiles and a limit of 3 sideloaded apps. Paid
membership removes both limits and unlocks TestFlight.

### Running in Xcode

```bash
xcodegen generate && open Shine.xcodeproj
```

## Pointing it somewhere else

The origin is written in exactly one place:

```swift
// Shine/App/ShineWebView.swift
enum ShineConfig {
    static let origin = URL(string: "https://shineaimobile.pages.dev/")!
}
```

Note the desktop app currently targets `https://shineai-9mr.pages.dev` - a
different host. Worth settling on one before shipping both.

## What the shell handles

- **Attachments** - WebKit presents its own upload panel for the site's file
  input, offering Take Photo, Photo Library and Browse. No delegate is needed,
  and `WKOpenPanelParameters` is iOS 18.4+ with no accept-type information, so
  overriding it would buy nothing.
- **Approvals** - the site uses `window.confirm` for its "Control PC" prompts.
  `WKWebView` drops those calls silently unless `runJavaScriptConfirmPanel...`
  is implemented, which would leave every approval hanging.
- **Microphone and camera** - `requestMediaCapturePermissionFor` grants the
  site's `getUserMedia` calls, which is what makes Shine Live work. Without it,
  `getUserMedia` is refused outright and the Info.plist usage strings alone
  never produce a prompt. Attachments need no code: WebKit presents the system
  upload panel, which offers Take Photo, Photo Library and Browse.
- **Downloads** - the download button on each code block, and generated images,
  are saved to `Documents/Downloads` and offered to the share sheet.
- **Links** - same-origin links load in place; anything else opens in Safari,
  because a web view with no address bar is not somewhere you want to be sent.
- **Persistence** - history, provider keys and the theme toggle live in
  localStorage, kept by the default persistent `WKWebsiteDataStore`.
- **Recovery** - a killed content process triggers a reload; a failed load shows
  a banner with a Retry button instead of a black screen.
- **Edge to edge** - the web view runs under the top safe area. The site's
  background layer is `position: fixed; inset: -18px` and its mobile header is
  `position: fixed; top: 0` with `env(safe-area-inset-top)` padding, and both
  anchor to the web view's viewport. Stopping the view at the safe area leaves a
  strip of the app's own background across the top that the site's background
  never reaches, which is what made a custom chat background look broken.

## Layout

```
project.yml                       XcodeGen spec - the project's source of truth
Shine/App/ShineApp.swift          @main entry point
Shine/App/ContentView.swift       SwiftUI shell, error banner, edge-to-edge layout
Shine/App/ShineWebView.swift      the WKWebView and all its delegates
Shine/App/Downloads.swift         download paths and the share sheet
Shine/Resources/                  icon, accent colour, launch screen
scripts/make-icon.ps1             regenerates the 1024px icon
scripts/build-ipa.sh              archive + export
```

The `.xcodeproj` is generated from `project.yml` and is gitignored, so the
project file can never quietly fall out of sync with the source. Edit the YAML.

## Regenerating the icon

```bash
pwsh -File scripts/make-icon.ps1
```

It draws at 1024px in 24bpp on purpose - iOS rejects an app icon that carries an
alpha channel, which a 32bpp ARGB surface would write even when fully opaque.
