# Releasing to TestFlight

Everything here after step 2 has to run on a Mac with Xcode. CI compiles the app and runs
unit tests, but it does not sign, archive, or upload — that needs your Apple Developer
certificates, which should never live in a repository.

## 1. Confirm the build is green

CI (`.github/workflows/build.yml`) compiles the app and runs the unit tests on every pull
request. Do not archive from a branch whose build is red.

```sh
xcodebuild build \
  -project "To Do.xcodeproj" \
  -scheme "To Do" \
  -destination "generic/platform=iOS"
```

## 2. Check the CloudKit Production schema — do not skip this

This is what broke v2.1. Adding a SwiftData property changes the CloudKit record type, and
if that change is only in Development, **Production silently rejects every save**. The app
keeps working locally and sync just stops, with no error anywhere. See commit `6f8a24b`.

Before every release:

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/) → container
   `iCloud.com.matodoapp.todo`.
2. Compare **Development** and **Production** schemas for `CD_TodoList`, `CD_TaskItem`,
   `CD_Contact`, `CD_Interaction`.
3. If Development has fields Production lacks, use **Deploy Schema Changes**.

Rules to keep the schema deployable:

- Every stored property needs a default value or must be optional.
- To-many relationships must be optional (`var interactions: [Interaction]?`).
- No `@Attribute(.unique)` — CloudKit does not support unique constraints.
- Schema changes are additive only. You cannot remove or retype a deployed field.

Version 2.3 adds no new properties, so nothing needs deploying for this release.

## 3. Version and build numbers

Set in `To Do.xcodeproj/project.pbxproj` for the app target (`com.matodoapp.todo`):

- `MARKETING_VERSION` — the user-visible version (currently `2.3`)
- `CURRENT_PROJECT_VERSION` — the build number (currently `15`)

App Store Connect rejects a version+build pair it has already seen. Already consumed:
2.0 (live), 2.1 build 3, 2.2 builds 11-14. **Always bump `CURRENT_PROJECT_VERSION` before
re-uploading**, even for an identical version string.

## 4. Signing prerequisites

One-time, in the [Apple Developer portal](https://developer.apple.com/account):

- Apple Distribution certificate installed in your login keychain.
- App ID `com.matodoapp.todo` with **iCloud (CloudKit)** and **Sign in with Apple**
  capabilities — these must match `To Do/To_Do.entitlements` exactly, or the upload is
  rejected with a provisioning-profile mismatch.
- An App Store provisioning profile for that App ID.

In Xcode: **Signing & Capabilities** → Team set, "Automatically manage signing" on.

## 5. Archive and upload

Via Xcode (simplest):

1. Select **Any iOS Device (arm64)** as the destination — you cannot archive to a simulator.
2. **Product → Archive**
3. In the Organizer: **Distribute App → TestFlight & App Store → Upload**

Or from the command line, with an
[App Store Connect API key](https://appstoreconnect.apple.com/access/integrations/api):

```sh
xcodebuild archive \
  -project "To Do.xcodeproj" \
  -scheme "To Do" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/Folio.xcarchive

xcodebuild -exportArchive \
  -archivePath build/Folio.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/export

xcrun altool --upload-app \
  -f "build/export/To Do.ipa" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

`ExportOptions.plist` is not committed — it holds your team ID. Minimal version:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>            <string>app-store-connect</string>
    <key>teamID</key>            <string>YOUR_TEAM_ID</string>
    <key>uploadSymbols</key>     <true/>
    <key>signingStyle</key>      <string>automatic</string>
</dict>
</plist>
```

## 6. After upload

- Processing takes 5-30 minutes before the build appears in TestFlight.
- **Export compliance**: the app makes no network calls of its own and uses only Apple's
  standard encryption, so the answer to the encryption question is *no*. Setting
  `ITSAppUsesNonExemptEncryption` to `<false/>` in `Info.plist` removes the prompt on
  every upload.
- Internal testers get the build immediately. External testers require Beta App Review.
- Watch for **ITMS-91053** (missing API declaration). `To Do/PrivacyInfo.xcprivacy`
  declares `NSUserDefaults` (CA92.1) via `@AppStorage`. If you add a dependency or start
  using file-timestamp or disk-space APIs, that manifest needs updating.

## 7. Smoke test on device before promoting

The paths most likely to break, and least covered by tests:

- Add and remove several email/phone rows in the contact editor, including the last one
  while its field has focus.
- Pick a contact photo, save, and confirm it appears on a second device (this is the
  CloudKit record-size path).
- Set a reconnect date, accept the notification prompt, then clear the date.
- Run Apple Contacts import twice and confirm no duplicates on the second run.
- Delete Account, then confirm tasks *and* contacts are gone on relaunch.

## Known blockers before a public release

- **Sign in with Apple**: Delete Account does not revoke the Apple ID token, which Apple
  requires. Revocation needs a signed `client_secret` and therefore a backend. The app has
  no server, so the realistic fix is to remove Sign in with Apple entirely — which also
  clears the Guideline 5.1.1(v) risk of gating a serverless app behind registration.
- Contacts import blocks the main thread; large address books risk a watchdog termination.

These do not block TestFlight. They do block App Store review.
