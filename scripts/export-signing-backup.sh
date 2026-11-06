#!/bin/zsh
#
# Backs up the two secrets every NotchTune release depends on, into a folder
# you choose:
#
#   notchtune-sparkle.key    the Sparkle EdDSA private key (account NotchTune)
#   notchtune-signing.p12    the "Open Island Dev Local" certificate and key
#
# Neither can be remade. A new certificate changes the app's designated
# requirement, so macOS drops every user's Camera, Calendar and Accessibility
# grants; without the Sparkle key, no installed copy will accept an update.
#
# The Sparkle key is written unencrypted, so choose encrypted storage. Restore
# steps are in docs/release-signing.md.
#
# The certificate goes through Keychain Access rather than `security export`,
# which can't pick one identity: it would export all of them.
#
# usage: zsh scripts/export-signing-backup.sh <destination-folder>

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
identity_name="Open Island Dev Local"
generate_keys="$repo_root/.build/artifacts/sparkle/Sparkle/bin/generate_keys"

destination="${1:-}"
if [[ -z "$destination" ]]; then
    echo "usage: zsh scripts/export-signing-backup.sh <destination-folder>" >&2
    exit 64
fi
[[ -x "$generate_keys" ]] || { echo "No $generate_keys: run 'swift package resolve' first." >&2; exit 1; }

key_path="$destination/notchtune-sparkle.key"
p12_path="$destination/notchtune-signing.p12"
for file in "$key_path" "$p12_path"; do
    [[ ! -e "$file" ]] || { echo "$file already exists." >&2; exit 1; }
done

echo "This writes your Sparkle private key, unencrypted, to:"
echo "  $key_path"
read -q "reply?Continue? [y/N] " || { echo; exit 1; }
echo

mkdir -p "$destination"
chmod 700 "$destination"
umask 077

echo "• Exporting the Sparkle key…"
"$generate_keys" --account NotchTune -x "$key_path"

echo
echo "• Now the certificate, by hand:"
echo "    1. Open Keychain Access, then login > My Certificates."
echo "    2. Select \"$identity_name\" and choose File > Export Items."
echo "    3. Save it as $p12_path with a strong password."
read "reply?Press Return when that's done. "

if [[ -s "$p12_path" ]]; then
    chmod 600 "$p12_path"
    echo "✓ Backed up to $destination. Keep it on encrypted storage."
else
    echo "No $p12_path yet: the Sparkle key is backed up, the certificate isn't." >&2
    exit 1
fi
