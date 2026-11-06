# Packaging

`zsh scripts/package-app.sh` turns the Swift package into a signed macOS app with
no Xcode project. For publishing one, see [releasing.md](releasing.md).

## What it does

1. Builds `NotchTuneApp`, `NotchTuneHooks` and `NotchTuneSetup` in release mode.
2. Assembles `output/package/NotchTune.app`, with the helpers in
   `Contents/Helpers/` so the app can find `NotchTuneHooks` once it leaves the
   checkout, and Sparkle.framework in `Contents/Frameworks/`.
3. Verifies the bundle, then smoke-tests a copy outside the repo.
4. Signs inside-out, then writes `NotchTune.zip` and `NotchTune.dmg`.

`NOTCHTUNE_EDDSA_PUBLIC_KEY` is required. For a real package, use the key from
`generate_keys --account NotchTune -p`. CI passes an all-zero key, which is
valid to package with and can't verify any update.

Builds target the host architecture: Apple Silicon, for what gets released.
`NOTCHTUNE_UNIVERSAL=true` adds `x86_64`, but Intel isn't a supported release.

## The smoke test

It catches an app that only works because SPM's resource accessor can fall back
to `.build/`. It runs the real binary, possibly on a Mac running the real app, so
it's kept away from everything of the user's: a harness scenario (no hook
installs, session discovery or Sparkle, and windows stay off screen), the bridge
off, a temp `HOME`, and a copy with its own bundle ID, `app.notchtune.smoke`.
The bundle ID matters because `cfprefsd` ignores `HOME` and `CFFIXED_USER_HOME`.

## Signing

The script picks the first of these it finds:

| Identity | Result |
|----------|--------|
| `NOTCHTUNE_SIGN_IDENTITY` | Developer ID: hardened runtime, plus notarization with `NOTCHTUNE_NOTARY_PROFILE` |
| `NOTCHTUNE_STABLE_SIGN_IDENTITY`, or `Open Island Dev Local` in the login keychain | Stable self-signed certificate, how releases are signed today |
| Nothing | Ad-hoc, with a warning. `NOTCHTUNE_REQUIRE_STABLE_SIGNING=1` makes this an error |

See [release-signing.md](release-signing.md). Entitlements are in
`config/packaging/NotchTuneApp.entitlements`.

## Gatekeeper

Builds aren't notarized, so macOS blocks the first launch of a download. On macOS
15 and later, right-click → **Open** no longer gets past this. Either:

- Try to open the app, then choose **Open Anyway** in System Settings → Privacy &
  Security; or
- Remove the quarantine flag, which also clears **"NotchTune is damaged"**:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/NotchTune.app"
  ```

## Optional overrides

- `NOTCHTUNE_APP_NAME`
- `NOTCHTUNE_BUNDLE_ID`
- `NOTCHTUNE_VERSION`
- `NOTCHTUNE_BUILD_NUMBER`
- `NOTCHTUNE_PACKAGE_ROOT`
- `NOTCHTUNE_BUNDLE_DIR`
- `NOTCHTUNE_ZIP_PATH`
- `NOTCHTUNE_DMG_PATH`
- `NOTCHTUNE_UNIVERSAL`
- `NOTCHTUNE_SIGN_IDENTITY`
- `NOTCHTUNE_STABLE_SIGN_IDENTITY`
- `NOTCHTUNE_REQUIRE_STABLE_SIGNING`
- `NOTCHTUNE_NOTARY_PROFILE`
