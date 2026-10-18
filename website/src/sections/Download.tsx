import { Download as DownloadIcon } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';

export default function Download() {
  const { version, downloadUrl } = useLatestRelease();
  return (
    <section id="download" className="section" aria-labelledby="download-title">
      <div className="wrap">
        <div className="download glass reveal">
          <img className="download-icon" src="/assets/icon.png" alt="" width={96} height={96} />
          <h2 id="download-title" className="h2">Get NotchTune.</h2>
          <p className="lede">Download the disk image, drag NotchTune to Applications, and look up.</p>
          <a className="btn btn-primary" href={downloadUrl}>
            <DownloadIcon aria-hidden="true" strokeWidth={2.2} />
            Download NotchTune {version}
          </a>
          <p className="download-meta">
            macOS 14 or later · Apple Silicon · Free ·{' '}
            <a href="https://github.com/dw2lam/NotchTune/releases">All releases</a>
          </p>
          <div className="install">
            <p>
              This early-access build isn’t signed yet, so macOS may say NotchTune is damaged the first time you open
              it. Run this once in Terminal, then open it again:
            </p>
            <code>xattr -dr com.apple.quarantine "/Applications/NotchTune.app"</code>
          </div>
        </div>
      </div>
    </section>
  );
}
