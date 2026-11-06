#!/bin/zsh
# clean-user-env.sh — Reset to a clean "new user" state for testing.
# Usage: zsh scripts/clean-user-env.sh [--dry-run]
#
# This removes all NotchTune (and legacy Open Island and Vibe Island) artifacts
# from the current user's environment, simulating a fresh install.

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

red()    { printf '\033[31m%s\033[0m\n' "$1"; }
green()  { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }

clean_path() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        if $DRY_RUN; then
            yellow "[dry-run] would remove: $path"
        else
            /bin/rm -rf "$path"
            green "removed: $path"
        fi
    fi
}

clean_glob() {
    local pattern="$1"
    for f in $~pattern(N); do
        clean_path "$f"
    done
}

echo "==> Quit NotchTune if running"
if ! $DRY_RUN; then
    pkill -x NotchTune 2>/dev/null || true
    pkill -f "NotchTune Dev" 2>/dev/null || true
    pkill -x NotchTuneApp 2>/dev/null || true
    pkill -x OpenIslandApp 2>/dev/null || true
    sleep 0.5
fi

uid="$(id -u)"

echo ""
echo "==> Cleaning NotchTune artifacts"

# --- Hook configurations ---
echo "--- Hook configs ---"

# Removes what NotchTune installed from an agent's JSON config: hook entries
# in either shape (Claude/Codex/Gemini/Antigravity nest commands under
# `hooks`, Cursor keeps them flat), its status line, its OpenCode plugin. It
# covers both the current and the OpenIsland names, because the support
# directory goes below and an entry left behind would point at a missing
# binary. Vibe Island hook entries belong to a different app and stay.
strip_json_config() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if $DRY_RUN; then
        yellow "[dry-run] would strip NotchTune entries from: $file"
        return 0
    fi
    python3 - "$file" <<'PYTHON' && green "cleaned $file" || red "could not clean $file"
import json, pathlib, sys

MARKERS = ('notchtunehooks', 'openislandhooks')
STATUS_LINE_MARKERS = ('notchtune', 'open-island', 'vibe-island')
PLUGIN_MARKERS = ('notchtune', 'open-island')

def is_ours(entry):
    if not isinstance(entry, dict):
        return False
    commands = [entry.get('command', '')]
    commands += [h.get('command', '') for h in entry.get('hooks', []) if isinstance(h, dict)]
    return any(marker in str(command).lower() for command in commands for marker in MARKERS)

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
changed = False

# Codex can keep events at the top level rather than under `hooks`.
hooks = data.get('hooks', data)
if isinstance(hooks, dict):
    for event in list(hooks):
        original = hooks[event]
        if not isinstance(original, list):
            continue
        kept = [entry for entry in original if not is_ours(entry)]
        if len(kept) != len(original):
            changed = True
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]
    if changed and not hooks and 'hooks' in data:
        del data['hooks']

status_line = data.get('statusLine')
if isinstance(status_line, dict) and any(m in status_line.get('command', '') for m in STATUS_LINE_MARKERS):
    del data['statusLine']
    changed = True

plugins = data.get('plugin')
if isinstance(plugins, list):
    kept = [p for p in plugins if not any(m in str(p) for m in PLUGIN_MARKERS)]
    if len(kept) != len(plugins):
        changed = True
        if kept:
            data['plugin'] = kept
        else:
            del data['plugin']

if changed:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
PYTHON
}

# Kimi reads TOML: each managed `[[hooks]]` block follows a marker comment.
strip_kimi_config() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if $DRY_RUN; then
        yellow "[dry-run] would strip NotchTune entries from: $file"
        return 0
    fi
    python3 - "$file" <<'PYTHON' && green "cleaned $file" || red "could not clean $file"
import pathlib, sys

MARKER = '# open-island: managed hook — do not edit'
path = pathlib.Path(sys.argv[1])
lines = path.read_text().split('\n')
kept, index = [], 0
while index < len(lines):
    if lines[index].strip() != MARKER:
        kept.append(lines[index])
        index += 1
        continue
    # The marker, its `[[hooks]]` header, and the keys up to the blank line
    # the installer writes after each block.
    index += 1
    while index < len(lines) and lines[index].strip() and lines[index].strip() != MARKER:
        index += 1
    if index < len(lines) and not lines[index].strip():
        index += 1
path.write_text('\n'.join(kept))
PYTHON
}

clean_install_records() {
    local dir="$1"
    clean_path "$dir/open-island-claude-hooks-install.json"
    clean_path "$dir/vibe-island-claude-hooks-install.json"
    clean_glob "$dir/settings.json.backup.*"
}

for d in ~/.claude ~/.qoder ~/.qwen ~/.factory ~/.codebuddy ~/.gemini; do
    strip_json_config "$d/settings.json"
    clean_install_records "$d"
done
clean_path ~/.gemini/open-island-gemini-hooks-install.json

# Antigravity shares the Gemini directory but keeps its own hooks file.
strip_json_config ~/.gemini/config/hooks.json
clean_path ~/.gemini/config/open-island-antigravity-hooks-install.json

strip_json_config ~/.codex/hooks.json
clean_path ~/.codex/open-island-codex-hooks-install.json
clean_path ~/.codex/open-island-install.json
clean_glob ~/.codex/'config.toml.backup.*'
clean_glob ~/.codex/'hooks.json.backup.*'

strip_json_config ~/.cursor/hooks.json
clean_path ~/.cursor/open-island-cursor-hooks-install.json
clean_glob ~/.cursor/'hooks.json.backup.*'

strip_kimi_config ~/.kimi/config.toml
clean_path ~/.kimi/open-island-kimi-hooks-install.json

# OpenCode: the bundled plugin file is `open-island.js` (not the install
# manifest name), and config.json references it.
clean_path ~/.config/opencode/plugins/open-island.js
clean_path ~/.config/opencode/notchtune-opencode-plugin-install.json
clean_path ~/.config/opencode/open-island-opencode-plugin-install.json
strip_json_config ~/.config/opencode/config.json

# --- Installed hooks binary ---
echo "--- Hooks binary ---"
clean_path ~/Library/Application\ Support/NotchTune
clean_path ~/Library/Application\ Support/OpenIsland
clean_path ~/Library/Application\ Support/VibeIsland

# --- Status line scripts ---
echo "--- Status line ---"
clean_path ~/.notchtune
clean_path ~/.open-island
clean_path ~/.vibe-island

# --- Session registry & app data ---
echo "--- App data ---"
clean_path ~/Library/Application\ Support/open-island
clean_path ~/Library/Caches/app.notchtune.dev
clean_path ~/Library/HTTPStorages/app.notchtune.dev

# --- Temp / socket files ---
echo "--- Temp files ---"
clean_path "/tmp/open-island-${uid}.sock"
clean_path /tmp/open-island-rl.json
clean_path /tmp/vibe-island-rl.json

# --- Installed app ---
echo "--- App bundle ---"
clean_path /Applications/NotchTune.app
clean_path ~/Applications/NotchTune.app
clean_path ~/Applications/NotchTune\ Dev.app
clean_path /Applications/Open\ Island.app
clean_path ~/Applications/Open\ Island.app
clean_path ~/Applications/Open\ Island\ Dev.app

# --- UserDefaults ---
echo "--- UserDefaults ---"
# Find the bundle ID used by the app
for bid in app.notchtune.dev app.openisland.dev app.vibeisland.dev; do
    plist=~/Library/Preferences/${bid}.plist
    if [[ -e "$plist" ]]; then
        if $DRY_RUN; then
            yellow "[dry-run] would remove defaults for: $bid"
        else
            defaults delete "$bid" 2>/dev/null || true
            green "removed defaults: $bid"
        fi
    fi
done

echo ""
if $DRY_RUN; then
    yellow "Dry run complete. Re-run without --dry-run to actually clean."
else
    green "Done! Environment is clean."
    echo ""
    echo "Next steps:"
    echo "  1. Install NotchTune.dmg from the latest release"
    echo "  2. Launch the app — you are now a fresh user"
fi
