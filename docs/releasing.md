# Releasing

How to cut a new GitHub release for NotchTune.

## Versioning

Follow [Semantic Versioning](https://semver.org/):

- **Patch** (0.1.x): bug fixes, doc updates, small improvements
- **Minor** (0.x.0): new features, non-breaking changes
- **Major** (x.0.0): breaking changes

## Checklist

1. **Confirm target**: ensure all intended changes are merged to `main`.
2. **Confirm signing secrets**: the repository must have `SPARKLE_PUBLIC_KEY`
   and `SPARKLE_PRIVATE_KEY` Actions secrets. See **EdDSA Key Setup** below.
3. **Tag the release**:
   ```bash
   git tag v<version>
   git push origin v<version>
   ```
4. **Watch the Release workflow**. It builds the app, signs the update archive,
   generates `appcast.xml`, and publishes all three release assets.
5. **Verify**: confirm the DMG, ZIP, and appcast are downloadable and use an
   older NotchTune build's **Check for Updates…** button.

For a local package without publishing:

```bash
public_key="$(
  .build/artifacts/sparkle/Sparkle/bin/generate_keys \
    --account NotchTune -p
)"
NOTCHTUNE_VERSION=<version> \
NOTCHTUNE_EDDSA_PUBLIC_KEY="$public_key" \
zsh scripts/package-app.sh
```

This produces `output/package/NotchTune.dmg` and
`output/package/NotchTune.zip`. To inspect its Sparkle signature manually:

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update \
  "output/package/NotchTune.zip"
```

## Release Notes Format

All release notes **must be bilingual** (English + Simplified Chinese). Use the following template:

```markdown
## NotchTune v<version> — <Title>

### Changes since v<prev> | 自 v<prev> 以来的变更

- <emoji> **Category**: English description (#PR)
  中文描述 (#PR)

---

## Installation | 安装说明

<< See "Installation Section" below >>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Change categories

| Emoji | Category | When to use |
|-------|----------|-------------|
| ✨ | Feature | New user-facing functionality |
| 🐛 | Fix | Bug fix |
| 📸/📋 | Docs | Documentation changes |
| ♻️ | Refactor | Code restructuring |
| 🏗️ | Infra | Build, CI, packaging changes |

## Installation Section

**Include in every release** until code signing is in place. Remove once we ship a signed & notarized build.

```markdown
## Installation | 安装说明

1. Download **NotchTune.dmg**, open it, and drag **NotchTune** to **Applications**.
   下载 **NotchTune.dmg**，打开后将 **NotchTune** 拖入 **Applications**。

2. Since this is an unsigned app, macOS may show **"NotchTune is damaged"** when you try to open it. Run this command in Terminal to fix it:
   由于应用未签名，macOS 可能会提示**「"NotchTune"已损坏」**。请在终端中执行以下命令：

   ```bash
   xattr -dr com.apple.quarantine "/Applications/NotchTune.app"
   ```

3. Requirements: **macOS 14+**, **Apple Silicon** (M1/M2/M3/M4/M5).
   系统要求：**macOS 14+**，**Apple Silicon**（M1/M2/M3/M4/M5）。

> ⚠️ **Note**: This is an unsigned early-access build. Code signing and notarization will be added once our Apple Developer account is approved.
> **注意**：这是未签名的早期测试版。代码签名和 Apple 公证将在 Developer 账号审核通过后添加。
```

## Assets

Every release ships three artifacts:

| File | Purpose |
|------|---------|
| `NotchTune.dmg` | Styled disk image with drag-to-Applications |
| `NotchTune.zip` | Sparkle-signed app archive |
| `appcast.xml` | Sparkle update feed for the latest release |

## Sparkle Appcast

The release workflow generates a signed `appcast.xml` asset for every tagged release.
Sparkle follows GitHub's latest-release redirect at:

```
https://github.com/dw2lam/NotchTune/releases/latest/download/appcast.xml
```

Each release needs a new `<item>` entry. Template:

```xml
<item>
    <title>Version X.Y.Z</title>
    <sparkle:version>BUILD_NUMBER</sparkle:version>
    <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    <pubDate>Thu, 06 Apr 2026 00:00:00 +0000</pubDate>
    <enclosure
        url="https://github.com/dw2lam/NotchTune/releases/download/vX.Y.Z/NotchTune.zip"
        type="application/octet-stream"
        sparkle:edSignature="PASTE_SIGNATURE_HERE"
        length="PASTE_LENGTH_HERE"
    />
</item>
```

### EdDSA Key Setup (one-time)

Generate a NotchTune-specific key pair with Sparkle's tool:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account NotchTune
```

This stores the private key in your macOS Keychain and prints the public key. Keep
the private key out of the repository. Configure the release workflow once:

```bash
tools=".build/artifacts/sparkle/Sparkle/bin"
"$tools/generate_keys" --account NotchTune -p \
  | gh secret set SPARKLE_PUBLIC_KEY
"$tools/generate_keys" --account NotchTune -x /tmp/notchtune-sparkle-private-key
gh secret set SPARKLE_PRIVATE_KEY < /tmp/notchtune-sparkle-private-key
rm /tmp/notchtune-sparkle-private-key
```

The public key is embedded as `SUPublicEDKey`; the private key is used only by
GitHub Actions to sign the update archive.

## Signing (future)

When `NOTCHTUNE_SIGN_IDENTITY` is set, `package-app.sh` handles codesign + notarization automatically. At that point:

1. Remove the "Installation Section" Gatekeeper instructions from future release notes.
2. Add `--verify` step to the checklist.

See [packaging.md](packaging.md) for signing details.
