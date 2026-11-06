import { useEffect, useState } from 'react';

const REPO = 'dw2lam/NotchTune';

export const REPO_URL = `https://github.com/${REPO}`;
// GitHub redirects this to the newest release's disk image, so the download
// never waits on the API below.
export const DOWNLOAD_URL = `${REPO_URL}/releases/latest/download/NotchTune.dmg`;

let request: Promise<string | null> | undefined;

// One API call per page view, for the version label and nothing else.
const latestVersion = () =>
  (request ??= fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: { Accept: 'application/vnd.github+json' },
  })
    .then((r) => (r.ok ? r.json() : null))
    .then((data) => String(data?.tag_name ?? '').replace(/^v/i, '') || null)
    .catch(() => null));

// The latest version, or null until it's known (or if GitHub can't be reached).
export function useLatestRelease(): string | null {
  const [version, setVersion] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    latestVersion().then((v) => {
      if (!cancelled) setVersion(v);
    });
    return () => {
      cancelled = true;
    };
  }, []);

  return version;
}
