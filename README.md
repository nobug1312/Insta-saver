# Insta Saver

A personal iOS app (SwiftUI, iOS 17+) for saving photos and videos from Instagram posts, reels, stories and highlights. Everything runs on the device; log in inside the app to download private content.

## Requirements

- A Mac with Xcode 15 or later
- An iPhone on iOS 17 or later, connected to the Mac with a cable
- An Apple ID (a free one is enough)
- [Homebrew](https://brew.sh) and XcodeGen

## Build and install on your iPhone

1. Install XcodeGen:
   ```
   brew install xcodegen
   ```
2. Generate the Xcode project from `project.yml`:
   ```
   xcodegen
   open InstaSaver.xcodeproj
   ```
3. In Xcode, select the **InstaSaver** target and open **Signing & Capabilities**:
   - Enable **Automatically manage signing**
   - Set **Team** to your Apple ID (add it under Xcode > Settings > Accounts)
   - If Xcode reports the bundle ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` (e.g. `com.<yourname>.instasaver`) and run `xcodegen` again
4. On the iPhone, turn on **Settings > Privacy & Security > Developer Mode** and restart.
5. Select your iPhone as the run destination and press **Run** (Cmd+R).
6. If the iPhone shows "Untrusted Developer" on first launch: **Settings > General > VPN & Device Management** > select your Apple ID > **Trust**.

With a free Apple ID the app expires after 7 days. Reconnect the phone and press Run in Xcode again to renew it.

## Usage

1. In Instagram, tap **•••** or **Share** on a post, reel or story and choose **Copy link**.
2. Open Insta Saver and tap **Paste**. The app looks up the media automatically.
3. All items are selected by default. Tap an item to deselect it, then tap **Save to Photos**.
4. For private accounts, stories and highlights, tap **Log in** first. Public posts work without logging in.

## Notes

- The app uses Instagram's unofficial web endpoints, which may stop working if Instagram changes them. That code lives in `InstaSaver/IGClient.swift`.
- Downloading a lot in a short time can get your account rate-limited or temporarily restricted. Consider logging in with a secondary account.
- The login cookie is stored in the Keychain on the device. **Log out** removes it.
- `InstaSaver.xcodeproj` is generated and ignored by git.
- `mockup.html` is a browser preview of the UI for reviewing the design without a Mac.
