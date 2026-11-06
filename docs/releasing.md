# Releasing

How to cut a NotchTune release. It's a manual flow, run from a Mac that holds
the signing certificate and the Sparkle key (see
[release-signing.md](release-signing.md)). No workflow publishes anything: CI
only builds, tests and packages to check that it all still works.

## Versioning

Follow [Semantic Versioning](https://semver.org/): patch for fixes, minor for
new features, major for breaking changes. Tags have **no `v` prefix** (`2.2.1`,
not `v2.2.1`).

The build number (`CFBundleVersion`) is `git rev-list --count HEAD`, and Sparkle
compares builds, not versions. `make-release-deltas.sh` stops if the build isn't
above the published one, which can happen on a branch with fewer commits. Fix
that by packaging from the right branch or setting `NOTCHTUNE_BUILD_NUMBER`.

## Before you start

- `Open Island Dev Local` in the login keychain, and the Sparkle key under the
  `NotchTune` account.
- `gh` signed in, `create-dmg` installed (`brew install create-dmg`), and Pillow
  for the brand scripts (`pip3 install Pillow`).
- `swift package resolve` has run, so Sparkle's tools exist in `.build/artifacts`.

## Steps

1. **Review what's going out.** Read every commit since the last tag rather than
   going from memory:

   ```bash
   git fetch origin
   git log <previous-tag>..origin/main --oneline
   ```

2. **Bump the version** in `scripts/package-app.sh`, `scripts/launch-dev-app.sh`,
   `website/package.json` and `website/src/hooks/useLatestRelease.ts`, then
   commit (`chore(release): version X.Y.Z`).

3. **Package.** This builds, smoke-tests, signs, and writes the DMG and ZIP to
   `output/package/`:

   ```bash
   public_key="$(.build/artifacts/sparkle/Sparkle/bin/generate_keys --account NotchTune -p)"
   NOTCHTUNE_REQUIRE_STABLE_SIGNING=1 \
   NOTCHTUNE_EDDSA_PUBLIC_KEY="$public_key" \
   zsh scripts/package-app.sh
   ```

   `NOTCHTUNE_REQUIRE_STABLE_SIGNING=1` makes it fail instead of falling back to
   an ad-hoc signature, which would drop users' permissions on update.

4. **Build the patches and the appcast:**

   ```bash
   zsh scripts/make-release-deltas.sh X.Y.Z
   ```

   This checks the build number against the published appcast, builds a delta
   from each of the last three releases (pass a count as the second argument to
   change that), proves each one rebuilds the new app exactly, signs them, and
   rewrites `appcast.xml`.

5. **Commit the appcast and push `main`:**

   ```bash
   git add appcast.xml
   git commit -m "chore(release): X.Y.Z appcast, build <build>, with delta patches"
   git push origin main
   ```

6. **Tag it**, annotated and with no `v`:

   ```bash
   git tag -a X.Y.Z -m "NotchTune X.Y.Z"
   git push origin X.Y.Z
   ```

7. **Publish.** Sparkle reads `appcast.xml` from the latest release, so this is
   the step that reaches users:

   ```bash
   gh release create X.Y.Z \
     output/package/NotchTune.dmg \
     output/package/NotchTune.zip \
     appcast.xml \
     output/package/deltas/*.delta \
     --title "NotchTune vX.Y.Z — Short Title" \
     --notes-file notes.md
   ```

8. **Verify.** Download the DMG and the appcast from the release, and let an
   older installed build pick up the update.

### Replacing a release

To ship a newer build under the same version, repeat steps 3 to 5 with the same
tag, then replace the assets:

```bash
gh release upload X.Y.Z \
  output/package/NotchTune.dmg output/package/NotchTune.zip \
  appcast.xml output/package/deltas/*.delta --clobber
```

`make-release-deltas.sh` patches from the build being replaced as well, and the
build number must still go up. Someone already holding a prepared update stays on
it until that installs, which `UpdateChecker` makes happen within about a day.

## Release notes

English only, from [.github/RELEASE_TEMPLATE.md](../.github/RELEASE_TEMPLATE.md).
Write them for the people using the app: what's better for them, not what
changed in the code.

Keep the template's Installation section in every release until builds are
notarized.

## Assets

| File | Purpose |
|------|---------|
| `NotchTune.dmg` | Disk image with drag-to-Applications, for new installs |
| `NotchTune.zip` | Sparkle-signed full app, the fallback for any installed build |
| `NotchTune-<new>-from-<old>.delta` | Signed patches from recent builds |
| `appcast.xml` | The update feed, also committed at the repo root |

Sparkle follows GitHub's latest-release redirect:

```
https://github.com/dw2lam/NotchTune/releases/latest/download/appcast.xml
```

## How updates reach people

Sparkle checks hourly, downloads in the background (a delta when one exists for
that build) and prepares the update. NotchTune then shows **Update** in the notch
and **Restart to Update** in Settings. It also installs on quit.

Holding a prepared update stops Sparkle from running any further check, so an
update left alone for a day applies itself once the user has been idle for five
minutes, no agent is waiting and Mirror is closed; the next check follows
from the new build. See `UpdateChecker` and `UpdateAutoInstall`.

With **Download updates automatically** off (Settings → General), Sparkle still
checks, Settings says what's available, and nothing downloads or restarts until
the user asks.
