import { Download as DownloadIcon } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';

export default function Download() {
  const { version, downloadUrl } = useLatestRelease();
  return (
    <section id="download" className="section download">
      <div className="dl-card glass-deep reveal">
        <img src="/assets/icon.png" alt="" className="dl-icon" />
        <h2>Get NotchTune</h2>
        <p className="dl-sub">Download the latest <code>.dmg</code>, drag it into Applications, and your notch starts earning its keep.</p>
        <a className="nt-cta" href={downloadUrl} target="_blank" rel="noopener">
          <DownloadIcon size={17} strokeWidth={2} />
          <span>Download v{version} for macOS</span>
        </a>
        <div className="dl-meta">
          <span>Latest release · v{version}</span>
          <span className="sep">·</span>
          <a href="https://github.com/dw2lam/NotchTune/releases" target="_blank" rel="noopener">All releases</a>
        </div>
        <p className="dl-note">Unsigned for now: if macOS blocks the first launch, right-click <b>NotchTune.app → Open</b>. macOS 14+.</p>
      </div>
    </section>
  );
}
