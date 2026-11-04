#!/bin/zsh
# Sparkle delta updates: patches from recent published builds to the one
# just packaged, so an update downloads only what changed (Figma-style)
# instead of the whole app. Writes the signed patches to
# output/package/deltas/ and appcast.xml with the full zip plus a
# <sparkle:deltas> entry per patch. Builds without a patch fall back to the
# full zip.
#
# usage: zsh scripts/make-release-deltas.sh <release-tag> [how-many-previous-releases]
# Run after scripts/package-app.sh; upload output/package/deltas/*.delta to
# the release alongside NotchTune.zip, NotchTune.dmg and appcast.xml.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tag="$1"
previous_count="${2:-3}"
repo="dw2lam/NotchTune"
bin="$repo_root/.build/artifacts/sparkle/Sparkle/bin"
package_dir="$repo_root/output/package"
zip_path="$package_dir/NotchTune.zip"
delta_dir="$package_dir/deltas"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[[ -f "$zip_path" ]] || { echo "No $zip_path: run scripts/package-app.sh first." >&2; exit 1; }

# The new app exactly as it ships: out of the zip.
mkdir -p "$work/new"
ditto -x -k "$zip_path" "$work/new"
new_app="$work/new/NotchTune.app"
plist="$new_app/Contents/Info.plist"
new_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
new_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
minimum_system="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null || echo 14.0)"

rm -rf "$delta_dir"
mkdir -p "$delta_dir"

deltas_xml=""
seen_builds=" $new_build "
# The newest releases, the tag itself included: re-shipping a version
# (same tag, newer build) patches from the build it replaces.
for previous_tag in $(gh release list --repo "$repo" --limit "$previous_count" --json tagName --jq '.[].tagName'); do
    dir="$work/old-$previous_tag"
    mkdir -p "$dir"
    if ! gh release download "$previous_tag" --repo "$repo" --pattern NotchTune.zip --dir "$dir" >/dev/null 2>&1; then
        echo "skip $previous_tag: no NotchTune.zip"
        continue
    fi
    ditto -x -k "$dir/NotchTune.zip" "$dir"
    old_app="$dir/NotchTune.app"
    old_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$old_app/Contents/Info.plist")"
    if [[ "$seen_builds" == *" $old_build "* ]]; then
        echo "skip $previous_tag: build $old_build already covered"
        continue
    fi
    seen_builds+="$old_build "

    delta_name="NotchTune-$new_build-from-$old_build.delta"
    delta_path="$delta_dir/$delta_name"
    # Format 3 reads on every Sparkle 2 release, so old builds can use it.
    "$bin/BinaryDelta" create --version 3 "$old_app" "$new_app" "$delta_path"

    # Prove the patch rebuilds the new app exactly before shipping it.
    check="$dir/check.app"
    "$bin/BinaryDelta" apply "$old_app" "$check" "$delta_path" >/dev/null
    if ! diff -rq "$new_app" "$check" >/dev/null; then
        echo "delta from $old_build does not rebuild $new_build" >&2
        exit 1
    fi

    signature="$("$bin/sign_update" --account NotchTune "$delta_path")"
    size="$(stat -f %z "$delta_path")"
    echo "delta $old_build -> $new_build: $(( size / 1024 )) KB"
    deltas_xml+="
                <enclosure
                    url=\"https://github.com/$repo/releases/download/$tag/$delta_name\"
                    sparkle:deltaFrom=\"$old_build\"
                    type=\"application/octet-stream\"
                    $signature
                />"
done

full_signature="$("$bin/sign_update" --account NotchTune "$zip_path")"
pub_date="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')"
deltas_block=""
if [[ -n "$deltas_xml" ]]; then
    deltas_block="
            <sparkle:deltas>$deltas_xml
            </sparkle:deltas>"
fi

cat > "$repo_root/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>NotchTune Updates</title>
        <link>https://github.com/$repo/releases</link>
        <description>Signed NotchTune releases.</description>
        <language>en</language>
        <item>
            <title>Version $new_version</title>
            <sparkle:version>$new_build</sparkle:version>
            <sparkle:shortVersionString>$new_version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$minimum_system</sparkle:minimumSystemVersion>
            <pubDate>$pub_date</pubDate>
            <enclosure
                url="https://github.com/$repo/releases/download/$tag/NotchTune.zip"
                type="application/octet-stream"
                $full_signature
            />$deltas_block
        </item>
    </channel>
</rss>
EOF
xmllint --noout "$repo_root/appcast.xml"
echo "appcast.xml: $new_version ($new_build), $(ls "$delta_dir" | wc -l | tr -d ' ') delta(s)"
