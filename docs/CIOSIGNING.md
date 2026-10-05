# CI signing: building a sideloadable .ipa

`.github/workflows/build-ipa.yml` ("Build signed IPA") archives the `myTeams`
scheme on a GitHub macOS runner. It signs the build manually with certificates
and profiles stored as repository secrets, exports an `.ipa`, and uploads it as
a run artifact. You then install that artifact on registered test iPhones.

This is **not** an App Store or TestFlight build. Nothing is uploaded to App Store Connect.

## One run

1. GitHub → **Actions** → **Build signed IPA** → **Run workflow**.
2. Pick the branch and an `export_method`:
   - `ad-hoc` (default): Apple Distribution certificate + Ad Hoc profiles.
     Installs on any device whose UDID is in the profiles.
   - `development`: Apple Development certificate + iOS App Development
     profiles. Uses the same secrets as `ios-signed-gate.yml`.
3. When the run finishes, download the `myTeams-ipa-<method>-<run#>-<sha7>`
   artifact from the run page's **Artifacts** section. It is kept for 14 days.
   The `build-ipa-logs-<run#>` artifact holds archive/export logs, the
   generated `ExportOptions.plist` and the profile checks.

The guard step fails within seconds and names any missing secrets for the
method you picked.

## Feather (unsigned) route

If you re-sign on the iPhone with [Feather](https://github.com/khcrysalis/Feather),
CI does not need any signing secrets.

1. GitHub → **Actions** → **Build signed IPA** → **Run workflow** → tick
   **`unsigned_feather`** (`export_method` is ignored) → **Run workflow**.
   The signed job is skipped. `build-ipa-unsigned` runs on every run of the
   workflow, ticked or not; ticking only skips the signed job. It builds Release
   with `CODE_SIGNING_ALLOWED=NO` and zips `Payload/myTeams.app` by hand. It
   fails if `myTeamWidgetExtension.appex` is not in
   `Payload/myTeams.app/PlugIns`. It then publishes a GitHub Release tagged
   `v1.0.N` (next after the highest existing `v1.0.*` tag) on the built commit.
2. Easiest: open the `v1.0.N` release (repo → **Releases**) and download its
   single asset, `myTeams-<tag>-unsigned.ipa`. No unzipping needed.
   Alternatively, download the `myteams-ipa-unsigned-<run#>-<sha7>` artifact
   (kept 14 days) and unzip it to get `MyTeams-unsigned.ipa`. The build log is
   in `build-ipa-logs-<run#>`.
3. Open the `.ipa` in Feather (share sheet → Feather, or import it in the app).
4. Sign it in Feather with your own certificate + provisioning profile, then install.

Notes:
- Feather signs every bundle with a **single** profile. The app and the widget
  normally have separate App IDs, both with the App Group
  `group.PolarReailty.Hawk-Nation`, so the widget or the shared App Group data
  may not work until you adjust the entitlements in Feather's entitlement
  editing.
- The device's UDID only has to be in whichever profile Feather signs with.
  None of the profiles or secrets above are involved.

## What the project needs (grounded in the repo)

| Thing | Value | Source |
|---|---|---|
| Scheme | `myTeams` (archive uses `Release`) | `myTeams.xcodeproj/xcshareddata/xcschemes/myTeams.xcscheme` |
| App target / bundle id | `myTeams` / `PolarReailty.Hawk-Nation` | `project.pbxproj:1068` |
| Widget target / bundle id | `myTeamWidgetExtension` / `PolarReailty.Hawk-Nation.myTeamWidget` | `project.pbxproj:1117` |
| Team | `68L4YU8U89` | `project.pbxproj:1035` |
| App entitlements | App Group `group.PolarReailty.Hawk-Nation`, iCloud key-value storage | `myTeams-app.entitlements` |
| Widget entitlements | App Group `group.PolarReailty.Hawk-Nation` | `myTeamWidget/myTeamWidget.entitlements` |

The "Reailty" spelling is intentional. It matches the developer portal, so leave it as is.

## Secrets

Add each one under repo **Settings → Secrets and variables → Actions → New
repository secret**, or use `gh secret set NAME < <(base64 -i file)`.

### ad-hoc (default)

| Secret | Contents |
|---|---|
| `APPLE_DIST_CERT_P12_BASE64` | Apple Distribution certificate + private key, `.p12`, base64 |
| `APPLE_DIST_CERT_P12_PASSWORD` | The password you set when exporting that `.p12` |
| `PROVISION_APP_ADHOC_BASE64` | Ad Hoc profile for `PolarReailty.Hawk-Nation`, base64 |
| `PROVISION_WIDGET_ADHOC_BASE64` | Ad Hoc profile for `PolarReailty.Hawk-Nation.myTeamWidget`, base64 |

### development (already used by `ios-signed-gate.yml`)

| Secret | Contents |
|---|---|
| `APPLE_CERT_P12_BASE64` | Apple Development certificate + private key, `.p12`, base64 |
| `APPLE_CERT_P12_PASSWORD` | `.p12` export password |
| `PROVISION_APP_BASE64` | iOS App Development profile for `PolarReailty.Hawk-Nation`, base64 |
| `PROVISION_WIDGET_BASE64` | iOS App Development profile for `PolarReailty.Hawk-Nation.myTeamWidget`, base64 |

The ad-hoc build gets its own secrets because an ad-hoc build needs a
*distribution* certificate and *Ad Hoc* profiles. The development credentials
the signed gate uses cannot sign one. Each step chooses which credential set to
use in bash, so an empty ad-hoc secret never silently falls back to the
development one.

### Exporting the certificate (.p12)

1. If you don't have an **Apple Distribution** certificate yet: Xcode →
   Settings → Accounts → your team → Manage Certificates → `+` → Apple
   Distribution. You can also create one on developer.apple.com → Certificates
   from a CSR made in Keychain Access.
2. Keychain Access → **login** keychain → **My Certificates**. Expand
   "Apple Distribution: … (68L4YU8U89)" and make sure the private key is under
   it. Right-click the certificate → **Export…** → `.p12`, and set a password.
3. `base64 -i cert.p12 | pbcopy`, then paste it into
   `APPLE_DIST_CERT_P12_BASE64`. Put the password into
   `APPLE_DIST_CERT_P12_PASSWORD`.

If you build the `.p12` with OpenSSL 3 instead, pass `-legacy`. Otherwise
`security import` on the runner may reject it.

### Creating the Ad Hoc profiles (two of them)

An explicit provisioning profile covers exactly **one** App ID. The app and the
widget extension are separate App IDs, and both have App Groups, so a wildcard
profile won't work. You need **one Ad Hoc profile per bundle id**.

1. developer.apple.com → **Certificates, Identifiers & Profiles → Identifiers**.
   Confirm that:
   - `PolarReailty.Hawk-Nation` has **App Groups** (with
     `group.PolarReailty.Hawk-Nation` assigned) and **iCloud** (key-value storage).
   - `PolarReailty.Hawk-Nation.myTeamWidget` has **App Groups** (same group).
2. **Devices** → register every test iPhone's UDID (see below).
3. **Profiles → `+` → Distribution → Ad Hoc** → App ID
   `PolarReailty.Hawk-Nation` → the Apple Distribution certificate that is in
   your `.p12` → select the test devices → name it (e.g. "HawkNation AdHoc") →
   Generate → Download.
4. Repeat for `PolarReailty.Hawk-Nation.myTeamWidget` (e.g. "HawkNation Widget
   AdHoc"), with the **same devices**.
5. `base64 -i HawkNation_AdHoc.mobileprovision | pbcopy` → `PROVISION_APP_ADHOC_BASE64`;
   `base64 -i HawkNationWidget_AdHoc.mobileprovision | pbcopy` → `PROVISION_WIDGET_ADHOC_BASE64`.

### Checking a profile before uploading it

```sh
security cms -D -i HawkNation_AdHoc.mobileprovision > /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :Name' /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /tmp/p.plist   # 68L4YU8U89.<bundle id>
/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' /tmp/p.plist          # false for Ad Hoc
/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' /tmp/p.plist
# or quickly: security cms -D -i file.mobileprovision | grep -A1 application-identifier
```

The workflow runs the same checks and fails on any mismatch: team, the
application-identifier for the expected bundle id, App Group, iCloud KVS (app
only), a non-empty device list, and whether the profile type fits the method.

## How manual signing overrides the project

The pbxproj uses `CODE_SIGN_STYLE = Automatic`. The workflow leaves it alone and
overrides it on the `xcodebuild` command line, where command-line settings win:

```
CODE_SIGN_STYLE=Manual
CODE_SIGN_IDENTITY="Apple Distribution"        # "Apple Development" for development
DEVELOPMENT_TEAM=<TeamIdentifier read from the profile>
PROVISIONING_PROFILE_SPECIFIER='$(SIGN_PROFILE_$(TARGET_NAME:c99extidentifier))'
SIGN_PROFILE_myTeams=<app profile Name>
SIGN_PROFILE_myTeamWidgetExtension=<widget profile Name>
OTHER_CODE_SIGN_FLAGS="--keychain <temp keychain>"
```

`xcodebuild` has no per-target `TARGET:SETTING=VALUE` form. The indirection in
`PROVISIONING_PROFILE_SPECIFIER` makes each target resolve to its own profile.
`ios-signed-gate.yml` uses the same trick. A `-showBuildSettings` pre-check
asserts the resolution and the bundle ids before the archive runs.

The team id is read from the profile's `TeamIdentifier` and must equal
`68L4YU8U89`. Profile names and UUIDs are also read from the profiles, so
nothing about a specific profile is hardcoded. Each profile is installed as
`<UUID>.mobileprovision` into both
`~/Library/MobileDevice/Provisioning Profiles` and
`~/Library/Developer/Xcode/UserData/Provisioning Profiles` (Xcode 16+).

The generated `ExportOptions.plist` contains:
- `method`: `release-testing` for ad-hoc, `debugging` for development. These are
  the Xcode 15.3+ names for `ad-hoc` and `development`.
- `signingStyle` = `manual`, `signingCertificate`, `teamID`.
- `provisioningProfiles`, which maps both bundle ids to their profile names.
- `compileBitcode` = false, `uploadSymbols` = false, `stripSwiftSymbols` = true,
  `thinning` = `<none>`.

`-allowProvisioningUpdates` is deliberately **not** passed. Manual signing must
not contact the developer portal, and the runner has no Apple ID or API key.

The workflow creates a throwaway keychain with a random password in
`$RUNNER_TEMP` and puts it first in the search list. It runs
`set-key-partition-list` so codesign can use the key without a prompt. An
`if: always()` step deletes the keychain, the installed profiles and the
archive.

Like the other workflows, this one uses the default Xcode of the `macos-26`
runner image, without `xcode-select`. The Diagnostics step prints the version.

## Sideloading the .ipa

1. Download the artifact from the run page. It is a zip, so unzip it to get `myTeams.ipa`.
2. Install with any of these:
   - **Apple Configurator** (Mac): connect the iPhone → select it → **Add → Apps → Choose from my Mac…** → pick the `.ipa`.
   - **devicectl** (Xcode 15+): `xcrun devicectl list devices`, then
     `xcrun devicectl device install app --device <UDID or name> myTeams.ipa`.
   - **libimobiledevice**: `ideviceinstaller -i myTeams.ipa` (newer versions: `ideviceinstaller install myTeams.ipa`).
   - Finder: drag the `.ipa` onto the iPhone in the device's General tab.
3. A development build needs **Developer Mode** on the iPhone (Settings →
   Privacy & Security → Developer Mode). An Ad Hoc build does not.

### The device's UDID must be in the profile

Ad Hoc and Development builds only install on devices listed in the embedded
profile. The "Verify IPA signature" step prints that device list. If the install
fails with "unable to install" or an integrity error, the UDID is probably
missing.

- **Find the UDID**: connect the iPhone and open Finder → select the iPhone →
  click the text under its name until the UDID appears (right-click to copy).
  Or Xcode → Window → Devices and Simulators → Identifier. Or run
  `xcrun devicectl list devices`.
- **Add it**: developer.apple.com → Devices → `+` → register the UDID. Then
  Profiles → edit **both** Ad Hoc profiles → tick the new device → Save →
  Download. Re-upload them to `PROVISION_APP_ADHOC_BASE64` /
  `PROVISION_WIDGET_ADHOC_BASE64` and run the workflow again. An existing `.ipa`
  will not pick up the new device.
- A paid account allows 100 devices per device family per membership year.

## Expiry and revocation

- Certificates last one year. A team can have at most **2** Apple
  Distribution certificates (shared with App Store signing). Revoking one
  invalidates every profile that uses it, so afterwards you must regenerate
  and re-upload both profiles **and** the `.p12`.
- Ad Hoc / Development profiles expire after one year, or when their
  certificate expires, whichever comes first. The profile step prints each
  profile's `ExpirationDate`.
- Ad Hoc builds already installed stop launching once the distribution
  certificate is revoked or the profile expires. Rebuild and reinstall.
- Any capability change on an App ID (e.g. adding push) invalidates its
  profiles. Regenerate them and update the secrets.
