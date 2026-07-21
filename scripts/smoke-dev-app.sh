#!/bin/zsh

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Open Island smoke runs only on macOS." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

timestamp="$(date +%Y%m%d-%H%M%S)"
artifact_dir="${NOTCHTUNE_HARNESS_ARTIFACT_DIR:-$repo_root/output/harness/smoke-$timestamp}"

export NOTCHTUNE_HARNESS_SCENARIO="${NOTCHTUNE_HARNESS_SCENARIO:-approvalCard}"
export NOTCHTUNE_HARNESS_PRESENT_OVERLAY="${NOTCHTUNE_HARNESS_PRESENT_OVERLAY:-1}"
export NOTCHTUNE_HARNESS_START_BRIDGE="${NOTCHTUNE_HARNESS_START_BRIDGE:-0}"
export NOTCHTUNE_HARNESS_BOOT_ANIMATION="${NOTCHTUNE_HARNESS_BOOT_ANIMATION:-0}"
export NOTCHTUNE_HARNESS_CAPTURE_DELAY_SECONDS="${NOTCHTUNE_HARNESS_CAPTURE_DELAY_SECONDS:-1}"
export NOTCHTUNE_HARNESS_AUTO_EXIT_SECONDS="${NOTCHTUNE_HARNESS_AUTO_EXIT_SECONDS:-2}"
export NOTCHTUNE_HARNESS_ARTIFACT_DIR="$artifact_dir"

mkdir -p "$artifact_dir"

echo "Launching NotchTuneApp smoke scenario '${NOTCHTUNE_HARNESS_SCENARIO}' for ${NOTCHTUNE_HARNESS_AUTO_EXIT_SECONDS}s"
swift run NotchTuneApp

report_path="$artifact_dir/report.json"
if [[ ! -f "$report_path" ]]; then
    echo "Smoke failed: missing harness report at $report_path" >&2
    exit 1
fi

png_count="$(find "$artifact_dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
if [[ "$png_count" -eq 0 ]]; then
    echo "Smoke failed: no PNG artifacts captured in $artifact_dir" >&2
    exit 1
fi

ax_count="$(find "$artifact_dir" -maxdepth 1 -name '*.ax.json' | wc -l | tr -d ' ')"
if [[ "$ax_count" -eq 0 ]]; then
    echo "Smoke failed: no accessibility artifacts captured in $artifact_dir" >&2
    exit 1
fi

python3 - "$report_path" <<'PY'
import subprocess
import sys

subprocess.run(
    [sys.executable, "scripts/validate-harness-artifacts.py", sys.argv[1]],
    check=True,
)
PY

echo "Artifacts written to $artifact_dir"
echo "NotchTuneApp smoke passed"
