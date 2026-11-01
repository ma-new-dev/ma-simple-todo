# Releasing to TestFlight

Step 0 runs anywhere. Everything from step 1 on needs a Mac with Xcode, your Apple
Distribution certificate, and access to the developer portal. CI compiles the app and runs
the tests, but it never signs, archives, or uploads — those need credentials that should
not live in a repository.

Current state: **version 3.0, build 20 ("MA Compass" on the home screen)**, on branch `compass-3.0`.

3.0 renames Folio to **Compass** (display name only: bundle ID `com.matodoapp.todo`, the
CloudKit container and the on-device store are unchanged, so it installs as an update) and
adds three tabs: Health, Food and Net Worth. It also adds the CRM table and catch-up mode.
Everything it adds to the data model is additive; nothing existing is renamed or retyped.

---

## 0. Get the branch and confirm it's green

```sh
git fetch origin
git checkout compass-3.0
git pull
```

Check the CI badge on the 3.0 pull request, or run locally:

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

### New in 3.0: two capabilities

The entitlements file now also requests:

- **HealthKit** (read-only: steps, active energy, exercise minutes), and
- **iCloud Documents** on the same container `iCloud.com.matodoapp.todo`, for the Net
  Worth file and the upgrade backups.

With automatic signing, Xcode adds both to the App ID the first time you archive. If the
upload fails with a provisioning error, open the App ID in the developer portal, tick
**HealthKit**, and under **iCloud** make sure both CloudKit and iCloud Documents are on with
the container assigned; then refresh the profile in Xcode.

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

### For 3.0 specifically: five new record types must reach Production

3.0 adds `CD_DailyMetric`, `CD_Workout`, `CD_HealthBrief`, `CD_MealOption` and
`CD_DishImage` (the last has an asset field for the photo). Until they exist in
**Production**, those records will not sync from TestFlight builds. Tasks and contacts are
unaffected either way.

The catch is the warning below: Development still carries leftover v2.1 fields, and
deploying would push them to Production permanently. So clean Development first:

1. In [CloudKit Console](https://icloud.developer.apple.com/dashboard/), select
   **`iCloud.com.matodoapp.todo`** → **Development** → **Reset Development Environment**.
   This resets Development's schema and data to match Production. Production data is not
   touched. (Development data is only what debug builds wrote.)
2. Run a **debug build of 3.0** from Xcode on your iPhone (signed in to your iCloud), and use
   each tab once so every new type gets written: open Health with WHOOP connected (writes
   DailyMetric, Workout, HealthBrief), open Food (MealOption) and wait until a dish picture
   appears (DishImage; needs Apple Intelligence on).
3. In **Schema → Record Types (Development)**, confirm the five new types exist and that
   `CD_TodoList` / `CD_TaskItem` have **no** `CD_supabaseId` or `CD_updatedAt`.
4. **Deploy Schema Changes** to Production. Check Production now lists all nine types:
   the four from 2.x plus the five above.

### ⚠️ Do not press "Deploy Schema Changes" reflexively

Your **Development** environment may still carry `CD_supabaseId` and `CD_updatedAt` on
`CD_TodoList` / `CD_TaskItem`, left over from the v2.1 experiments. Those were later marked
`@Transient` and are not used by any current build.

**CloudKit schema changes are additive and permanent.** You cannot remove or retype a field
once it is deployed to Production. Deploying Development → Production while those leftovers
exist would push them into Production forever.

So: deploy **only** after resetting Development as described above, so the only changes
pending are the ones the current app actually writes.

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

### People: table and catch-up (on iPad or the Mac)

- [ ] People → Contacts shows a table. Click a column header: it sorts.
- [ ] Click a Priority cell → pick High. Click Reconnect → "2 weeks". Click Tags → toggle a tag.
- [ ] ⌘-click three rows → the toolbar shows "3 selected" → Mark contacted today → Message.
      All three show "Today" under Last contacted.
- [ ] Double-click a row → the contact's page opens.
- [ ] Catch Up → work through two cards with the M / 1 / → keys. "All caught up" at the end.
- [ ] On iPhone: swipe a contact row right → Contacted.

### Health

- [ ] Settings (gear) → paste the WHOOP client ID and secret (same as Baseline) → Connect.
      Sign in; the sheet closes and shows Connected.
- [ ] Back on Health, pull to refresh: recovery ring, six tiles and the Going well / Watch /
      Work on brief appear (written on-device by Apple Intelligence; plain computed lines if
      it is off). Spot-check recovery, HRV and sleep against the WHOOP app.
- [ ] The Apple Health prompt asks for steps, active energy and exercise minutes only.

### Food

- [ ] Food shows four cards for the current meal, each with a one-line reason. Swipe right,
      swipe left, tap Having this.
- [ ] With Apple Intelligence on, the top card gets an Image Playground illustration within
      a minute (only while the app is open).
- [ ] "This week" counts the picked meal (protein today, vegetables, paneer days).
- [ ] Next morning, the new options avoid what you skipped.

### Net Worth

- [ ] After first opening the tab, `~/Library/Mobile Documents/iCloud~com~matodoapp~todo/Documents/`
      exists on the Mac (Finder: iCloud Drive → Compass). Copy `networth.json` in (see
      `docs/networth.md`); pull to refresh shows it. The eye button hides amounts.

### Upgrade safety net

- [ ] iCloud Drive → Compass → Backups holds `compass-backup-3.0-19-<date>.json` with your
      lists, tasks and contacts.

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
   - **Uncheck "Manage Version and Build Number"** — the project already sets 3.0 / 18, and
     letting Xcode manage it can produce a build number you did not intend.
6. Let it re-sign automatically, review the summary, **Upload**.

### If the upload is rejected

- *90129, display name already taken* — Apple checks the home-screen name against every
  app on the store, even for TestFlight-only builds. 3.0 (18) failed as "Compass"; the
  display name is now "MA Compass". The upload itself succeeds and the failure only shows
  under TestFlight → Build Uploads, so check there after every upload.
- *Provisioning profile mismatch* — the App ID is missing the iCloud capability, or the
  CloudKit container is not assigned to it. Fix in the portal, then in Xcode use
  Signing & Capabilities → the refresh arrow next to the profile.
- *Duplicate build* — App Store Connect has already seen 3.0 (19). Bump
  `CURRENT_PROJECT_VERSION` and archive again.
- *ITMS-91053, missing API declaration* — something now uses a required-reason API that
  `To Do/PrivacyInfo.xcprivacy` does not declare. The message names the API; add it with
  the matching reason code.

---

## 5. After upload

- Processing takes 5–30 minutes before the build appears in TestFlight.
- **Export compliance**: the app's only network calls are HTTPS to WHOOP through Apple's
  URLSession, which is exempt standard encryption, so the answer is *no*. The brief, meal
  choices and pictures run on-device. Adding `ITSAppUsesNonExemptEncryption` =
  `<false/>` to `Info.plist` removes the prompt on every future upload.
- Internal testers get the build immediately. External testers require Beta App Review.

### The upgrade test — do this on TestFlight, not locally

Install 3.0 over the 2.3 (17) TestFlight build you use today. Do not delete the app first.

- [ ] Your lists, tasks and contacts are all there.
- [ ] iCloud Drive → Compass → Backups has the 3.0 backup file.
- [ ] A task added on the iPhone appears on the Mac app (and vice versa).

This was rehearsed in the simulator: a 2.3 store with 3 lists, 17 tasks, 8 contacts and 8
interactions opened in 3.0 with every record intact and the five new tables added. If data
is missing on a real device, **stop and do not promote the build**; the backup file holds a
readable copy.

## Known gaps

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
- HealthKit is unavailable when the app runs on the Mac; Health shows WHOOP data only there.
- The Net Worth file is produced on the Mac. If the Mac is off for a refresh, the tab shows
  the previous snapshot with its date.
