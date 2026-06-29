import { useEffect, useState } from 'react';

const REPO = 'dw2lam/NotchTune';

export interface ReleaseInfo {
  version: string;
  downloadUrl: string;
}

const FALLBACK: ReleaseInfo = {
  version: '0.1.2',
  downloadUrl: 'https://github.com/dw2lam/NotchTune/releases/latest',
};

// Fetches the latest GitHub release; prefers the .dmg asset, falls back to static.
export function useLatestRelease(): ReleaseInfo {
  const [info, setInfo] = useState<ReleaseInfo>(FALLBACK);

  useEffect(() => {
    let cancelled = false;
    fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
    })
      .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
      .then((data: any) => {
        if (cancelled) return;
        const v = String(data.tag_name || '').replace(/^v/i, '');
        if (!v) return;
        const dmg = (data.assets || []).find((a: any) => /\.dmg$/i.test(a.name));
        setInfo({ version: v, downloadUrl: dmg ? dmg.browser_download_url : data.html_url });
      })
      .catch(() => {/* keep fallback */});
    return () => {
      cancelled = true;
    };
  }, []);

  return info;
}
