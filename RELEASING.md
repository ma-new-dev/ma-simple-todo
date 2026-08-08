# Releasing to TestFlight

Step 0 runs anywhere. Everything from step 1 on needs a Mac with Xcode, your Apple
Distribution certificate, and access to the developer portal. CI compiles the app and runs
the tests, but it never signs, archives, or uploads — those need credentials that should
not live in a repository.

Current state: **version 2.3, build 17**, on branch `claude/explore-app-changes-nyjj9`.

---

## 0. Get the branch and confirm it's green

```sh
git fetch origin
git checkout claude/explore-app-changes-nyjj9
git pull
```

Check the CI badge on [PR #1](https://github.com/ma-new-dev/ma-simple-todo/pull/1), or run
locally:

```sh
xcodebuild build \
  -project "To Do.xcodeproj" \
  -scheme "To Do" \
  -destination "generic/platform=iOS"
```

Do not archive from a branch whose build is red.

---

## 1. Signing setup

### What you need

- **Apple Distribution** certificate in your login keychain. Check with
  Xcode → Settings → Accounts → your Apple ID → Manage Certificates. If there's no
  "Apple Distribution" row, click **+** and create one.
- App ID `com.matodoapp.todo` with the **iCloud (CloudKit)** capability enabled, and the
  CloudKit container `iCloud.com.matodoapp.todo` assigned to it.
- In Xcode: select the **To Do** target → **Signing & Capabilities** → your Team selected,
  **Automatically manage signing** checked.

### About Sign in with Apple

2.3 removes Sign in with Apple. `com.apple.developer.applesignin` is no longer in
`To Do/To_Do.entitlements`, so the binary does not request it.

**Recommendation: leave the capability enabled on the App ID.** Do not turn it off.

App Review looks at the entitlements the binary requests, not at what the App ID permits.
A provisioning profile may grant more than the app uses — the app's entitlements only have
to be a *subset* of the profile's, so nothing fails validation. Meanwhile, turning the
capability off means regenerating profiles, and users who previously signed in have a
"Folio" entry under Settings → Apple ID → Sign in with Apple that is better left
undisturbed.

If you want to clean it up later, do it as its own change once 2.3 is out and stable — not
as part of this release.

---

## 2. Check the CloudKit schema

This is what broke v2.1. Adding a SwiftData property changes the CloudKit record type, and
if the change only exists in Development, **Production silently rejects every save**. The
app keeps working locally and sync just stops, with no error surfaced anywhere. See commit
`6f8a24b`.

### For 2.3 specifically

**2.3 adds no new properties, so no deploy should be needed.** This step is a verification,
not an action.

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard/).
2. Select the container **`iCloud.com.matodoapp.todo`**.
3. Go to **Schema → Record Types**, and use the environment switcher to compare
   **Development** and **Production**.
4. Confirm all four record types exist in **Production**:
   `CD_TodoList`, `CD_TaskItem`, `CD_Contact`, `CD_Interaction`.

### ⚠️ Do not press "Deploy Schema Changes" reflexively

Your **Development** environment may still carry `CD_supabaseId` and `CD_updatedAt` on
`CD_TodoList` / `CD_TaskItem`, left over from the v2.1 experiments. Those were later marked
`@Transient` and are not used by any current build.

**CloudKit schema changes are additive and permanent.** You cannot remove or retype a field
once it is deployed to Production. Deploying Development → Production while those leftovers
exist would push them into Production forever.

So: deploy **only** if you find a field the current app actually writes that is missing
from Production. For 2.3, the expected outcome is that you find nothing and deploy nothing.

### Rules to keep the schema deployable in future

- Every stored property needs a default value or must be optional.
- To-many relationships must be optional (`var interactions: [Interaction]?`).
- No `@Attribute(.unique)` — CloudKit does not support unique constraints.
- Schema changes are additive only.

---

## 3. Smoke test on device

Green CI means it compiles and the model logic holds. It says nothing about whether the UI
works. Build to a real device from Xcode (**⌘R** with your iPhone selected) and walk
through the paths this release changed.

### Tasks

- [ ] Create a list. **Tap it** — it should open, not start a rename.
- [ ] Rename a list via swipe-right and via long-press → Rename.
- [ ] Tap **Edit** in the Lists toolbar, drag to reorder, tap Done. Reopen the app and
      confirm the order stuck.
- [ ] Add a task. Tap its circle — it should complete in **one tap, with no dialog**, and
      an Undo bar should appear.
- [ ] Tap **Undo** — the task returns to the active list.
- [ ] Complete two tasks in sequence; expand **Completed** and confirm the most recent one
      is at the top.
- [ ] Rename and reorder tasks; delete a task.

### Contacts

- [ ] Add a contact. Add three email rows, then **delete the middle one**, then delete the
      last one while its field still has focus. (This was an index-out-of-range crash.)
- [ ] Pick a contact photo, save, reopen — the photo persists.
- [ ] Swipe a contact row → **Edit** — the edit sheet should actually open.
- [ ] Delete a contact and confirm the dialog shows the right name and doesn't crash.
- [ ] Check avatar colours are the **same** after force-quitting and relaunching.
- [ ] Set a **reconnect date** → accept the notification permission prompt → reopen and
      **Clear Reconnect Date**; it should clear immediately without needing Set.
- [ ] Import Apple Contacts on a large address book: the spinner should animate and the app
      stay responsive. **Run it a second time** — it should import 0 new contacts.
- [ ] Confirm there is only **one** navigation bar in the People tab and the search field
      sits under the "Contacts" title.

### Destructive

- [ ] **Erase All Data** → confirm tasks *and* contacts are both gone after relaunch.

---

## 4. Archive and upload

1. In Xcode, set the run destination to **Any iOS Device (arm64)**. You cannot archive to a
   simulator.
2. **Product → Archive**. Wait for the build.
3. The Organizer opens. Select the archive → **Distribute App**.
4. Choose **App Store Connect** → **Upload**.
5. On the options screen:
   - Leave **Upload your app's symbols** checked (needed for readable crash reports).
   - **Uncheck "Manage Version and Build Number"** — the project already sets 2.3 / 17, and
     letting Xcode manage it can produce a build number you did not intend.
6. Let it re-sign automatically, review the summary, **Upload**.

### If the upload is rejected

- *Provisioning profile mismatch* — the App ID is missing the iCloud capability, or the
  CloudKit container is not assigned to it. Fix in the portal, then in Xcode use
  Signing & Capabilities → the refresh arrow next to the profile.
- *Duplicate build* — App Store Connect has already seen 2.3 (17). Bump
  `CURRENT_PROJECT_VERSION` and archive again.
- *ITMS-91053, missing API declaration* — something now uses a required-reason API that
  `To Do/PrivacyInfo.xcprivacy` does not declare. The message names the API; add it with
  the matching reason code.

---

## 5. After upload

- Processing takes 5–30 minutes before the build appears in TestFlight.
- **Export compliance**: the app makes no network calls of its own and uses only Apple's
  standard encryption, so the answer is *no*. Adding `ITSAppUsesNonExemptEncryption` =
  `<false/>` to `Info.plist` removes the prompt on every future upload.
- Internal testers get the build immediately. External testers require Beta App Review.

### The upgrade test — do this on TestFlight, not locally

Removing the sign-in gate is the riskiest part of 2.3, and it can only be tested honestly
as a real upgrade. It has to happen here rather than in step 3, because installing a
development-signed build over an App Store install does not reliably reproduce a real
upgrade — the signing identity differs and the system may replace the app rather than
update it.

1. On a test device, install **the current App Store version (2.0)**.
2. Sign in, create a list with a few tasks, and add a contact.
3. Install the **2.3 TestFlight build** over it (do not delete the app first).
4. Confirm:
   - [ ] The app opens straight to the task list, with no sign-in screen.
   - [ ] The list, tasks, and contact from 2.0 are all still there.
   - [ ] Changes still sync to a second device signed into the same iCloud account.

If data is missing at step 4, **stop and do not promote the build.** The store file is
unchanged by this release, so missing data would point at something more fundamental than
the sign-in removal.

---

## Known gaps, not addressed in 2.3

- `Contact.id` and `Interaction.id` are not unique. Two devices creating the same logical
  contact before syncing produce duplicates that nothing reconciles. CloudKit forbids
  `@Attribute(.unique)`, so this needs application-level merging.
- Contact photos are downsampled on pick and on import, but any photo stored by an earlier
  build is still full-resolution and may exceed CloudKit's ~1 MB record limit. Those
  contacts will not sync until the photo is re-picked.
- The storage-failure screen covers `ModelContainer(for:)` throwing. It does not cover
  CloudKit failing asynchronously afterwards, which is why an unsigned build still dies on
  launch. A signed build with the iCloud entitlement does not hit that path.
- UI tests cover the task flows only; the CRM tab has no automated coverage.
