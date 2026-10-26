# macOS Deployment, Packaging & Notarization Guide

A step-by-step reference for archiving a macOS application in Xcode, packaging it into a drag-and-drop `.dmg` or `.pkg` installer, notarizing it with Apple's Notary service, and verifying Gatekeeper readiness.

---

## 1. Prerequisites & First-Time Setup

### Required Certificates (Xcode)
1. Open **Xcode > Settings > Accounts**.
2. Select your Apple Developer account and click **Manage Certificates…**.
3. Ensure you have a valid **Developer ID Application** certificate installed in your Keychain (click **`+` > Developer ID Application** if missing).
   * *Note: If you also plan to sign `.pkg` installers, create a **Developer ID Installer** certificate as well.*

### Required Target Capabilities in Xcode
Before archiving any macOS app for external distribution, Apple's Notary service requires **Hardened Runtime**:
1. Select your project in the Xcode Project Navigator, select the **App Target**, and open the **Signing & Capabilities** tab.
2. Ensure **Hardened Runtime** is added (`+ Capability > Hardened Runtime`).
3. If your app uses AppleScript / `System Events` automation, check **Apple Events** under Hardened Runtime's *Resource Access* section (`com.apple.security.automation.apple-events = true`) and ensure `NSAppleEventsUsageDescription` is set in **Info**.

### Store `notarytool` Credentials in Keychain (One-Time Setup)
To allow command-line notarization of `.dmg`, `.pkg`, or `.zip` files without typing passwords into scripts:

1. Sign in to **[account.apple.com](https://account.apple.com/)**.
2. Go to **Sign-In and Security > App-Specific Passwords** and generate a new password (e.g., labeled `Xcode Notarytool`).
3. Run the following command in Terminal to save the credentials securely in your macOS Keychain under the profile name `"notary-profile"`:

```bash
xcrun notarytool store-credentials "notary-profile" \
  --apple-id "<YOUR_APPLE_ID_EMAIL>" \
  --team-id "<YOUR_TEAM_ID>" \
  --password "<XXXX-XXXX-XXXX-XXXX>"
```

---

## 2. Archive & Export the Notarized `.app` from Xcode

1. Open your `.xcodeproj` or `.xcworkspace` in Xcode.
2. In the top toolbar or menu bar, set the build destination to **Product > Destination > Any Mac (arm64, x86_64)**.
3. Select **Product > Archive**.
4. Once the build finishes and the **Organizer** window opens:
   * Select your new archive and click **Distribute App**.
   * Choose **Direct Distribution** (signs with your *Developer ID Application* certificate and submits to Apple for notarization).
   * Click **Distribute** and wait ~1–2 minutes until the status changes to **Ready to Distribute**.
   * Click **Export** and save the exported `<AppName>.app` to a local release folder (e.g., `./dist/`).

---

## 3. Option A: Build & Notarize a Drag-to-Applications `.dmg`

Wrapping your exported `.app` in a `.dmg` with a shortcut to `/Applications` is the standard distribution method for macOS apps.

### Step 1: Install `create-dmg`
Choose either the Homebrew shell tool (customizable layout) or the Node.js tool (automatic built-in background arrow):

* **Option 1 — Homebrew `create-dmg` (Customizable):**
  ```bash
  brew install create-dmg
  ```
  Build the `.dmg`:
  ```bash
  create-dmg \
    --volname "<App Display Name>" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "<AppName>.app" 175 190 \
    --hide-extension "<AppName>.app" \
    --app-drop-link 425 190 \
    "<AppName>-Installer.dmg" \
    "/path/to/exported/<AppName>.app"
  ```
  *(Optional: Add `--background "dmg-background.png"` if you have a `600x400` background image.)*

* **Option 2 — Node `create-dmg` (Zero-Config Default Arrow Background):**
  ```bash
  npm install --global create-dmg
  create-dmg "/path/to/exported/<AppName>.app"
  ```

### Step 2: Notarize & Staple the `.dmg`
Even if the `.app` inside the `.dmg` is already notarized, you should submit and staple the outer `.dmg` container so Gatekeeper trusts the disk image immediately upon download:

```bash
# 1. Submit the DMG to Apple's Notary service and wait for completion
xcrun notarytool submit "<AppName>-Installer.dmg" \
  --keychain-profile "notary-profile" \
  --wait

# 2. Staple the notarization ticket directly to the DMG file
xcrun stapler staple "<AppName>-Installer.dmg"
```

---

## 4. Option B: Build & Notarize a Standard `.pkg` Installer

If you prefer a double-click wizard installer (or need to deploy via MDM) that installs directly into `/Applications`:

```bash
# 1. Build and sign the .pkg (replace <DEVELOPER_ID_INSTALLER_CERT_NAME> with your Developer ID Installer identity, or omit --sign to build unsigned first)
pkgbuild \
  --component "/path/to/exported/<AppName>.app" \
  --install-location "/Applications" \
  --sign "Developer ID Installer: <Your Name or Organization> (<YOUR_TEAM_ID>)" \
  "<AppName>-Installer.pkg"

# 2. Submit the .pkg for notarization
xcrun notarytool submit "<AppName>-Installer.pkg" \
  --keychain-profile "notary-profile" \
  --wait

# 3. Staple the notarization ticket to the .pkg
xcrun stapler staple "<AppName>-Installer.pkg"
```

---

## 5. Option C: Distributing as a `.zip` Archive

If you distribute a simple `.zip` instead of a `.dmg` or `.pkg`, **always use `ditto`** instead of Finder's "Compress" or the standard `zip` command so resource forks and code signatures stay intact:

```bash
# Create a signature-safe .zip archive from the exported, notarized .app
ditto -c -k --keepParent "/path/to/exported/<AppName>.app" "<AppName>.zip"
```
*(Note: `.zip` files cannot have a ticket stapled to the outer `.zip`, so make sure `xcrun stapler staple "/path/to/exported/<AppName>.app"` was run on the `.app` before zipping—Xcode's "Direct Distribution" export does this automatically.)*

---

## 6. Verification Checklist (Run Before Publishing)

Run these commands in Terminal to verify that your `.app` and `.dmg` are properly signed, entitled, notarized, and stapled:

```bash
# 1. Verify the .app code signature (strict deep check)
codesign --verify --deep --strict --verbose=2 "/path/to/exported/<AppName>.app"

# 2. Inspect baked-in entitlements (e.g. com.apple.security.automation.apple-events)
codesign -d --entitlements - "/path/to/exported/<AppName>.app"

# 3. Verify Gatekeeper acceptance on the .app
spctl -a -vvv -t exec "/path/to/exported/<AppName>.app"

# 4. Verify the stapled notarization ticket on the .dmg (or .pkg)
xcrun stapler validate "<AppName>-Installer.dmg"
spctl -a -vvv -t open --context context:primary-signature "<AppName>-Installer.dmg"
```

### Troubleshooting Notarization Failures
If `xcrun notarytool submit` ever returns `Invalid`, copy the `id` UUID from the terminal output and fetch Apple's detailed JSON error log:

```bash
xcrun notarytool log <SUBMISSION_ID_UUID> --keychain-profile "notary-profile"
```