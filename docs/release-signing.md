# Release Signing

NotchTune has no Developer ID and isn't notarized. A release depends on two
secrets that live only in the release Mac's login keychain, and **neither can be
remade**:

| Secret | What it does | If it's lost |
|--------|--------------|--------------|
| `Open Island Dev Local` certificate | Signs the app, so its designated requirement stays the same from build to build | A new certificate reads as a new app: macOS drops every user's Camera, Calendar and Accessibility grants |
| Sparkle EdDSA key (Keychain account `NotchTune`) | Signs updates; the public half is `SUPublicEDKey` in every installed app | Installed copies reject anything signed with a new key, so everyone has to reinstall by hand |

## The certificate

`scripts/setup-dev-signing.sh` creates it once: a 10-year self-signed code-signing
certificate, imported into the login keychain and trusted for code signing only.
`package-app.sh` finds it by name, or takes a hash in
`NOTCHTUNE_STABLE_SIGN_IDENTITY`.

Set `NOTCHTUNE_REQUIRE_STABLE_SIGNING=1` for a release so that a missing identity
stops the build. Otherwise the script falls back to an ad-hoc signature, whose
designated requirement is the build's own hash.

The script signs without the hardened runtime here: its library validation would
refuse Sparkle.framework, which has no team ID to match.

Don't run `setup-dev-signing.sh` on a new Mac to get going: it would make a
different certificate. Restore the backup.

## The Sparkle key

Generated once with `generate_keys --account NotchTune`, which stores the private
key in the Keychain and prints the public one. `package-app.sh` needs the public
key in `NOTCHTUNE_EDDSA_PUBLIC_KEY`; `make-release-deltas.sh` signs with the
private key through `sign_update --account NotchTune`.

## Backing up

```bash
zsh scripts/export-signing-backup.sh /Volumes/YourEncryptedDisk/notchtune-keys
```

It prompts first, then exports the Sparkle key to `notchtune-sparkle.key`
(unencrypted, so use encrypted storage) and walks you through exporting the
certificate from Keychain Access as `notchtune-signing.p12`, with a password you
choose. Keychain Access does the certificate because `security export` can't pick
out one identity.

## Restoring on a new Mac

```bash
keychain="$HOME/Library/Keychains/login.keychain-db"

# The certificate: codesign needs access, and the trust override makes it valid.
security import notchtune-signing.p12 -k "$keychain" -T /usr/bin/codesign
security find-certificate -c "Open Island Dev Local" -p > cert.pem
security add-trusted-cert -p codeSign -k "$keychain" cert.pem
rm cert.pem

# The Sparkle key, after `swift package resolve`.
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account NotchTune -f notchtune-sparkle.key
```

Check both before releasing: `security find-identity -p codesigning -v` lists the
identity, and `generate_keys --account NotchTune -p` prints the same public key as
a shipped build's `SUPublicEDKey`.

## If a Developer ID arrives

`package-app.sh` already handles it: set `NOTCHTUNE_SIGN_IDENTITY` for hardened
runtime signing, and `NOTCHTUNE_NOTARY_PROFILE` (a `notarytool store-credentials`
profile) to notarize and staple. Sparkle accepts the change of identity because
the EdDSA key stays the same, but users grant permissions once more. The
Installation section can then leave the release notes.
