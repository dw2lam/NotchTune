import { Download as DownloadIcon } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import { PlateImage } from '../components/Plate';

export default function Download() {
  const { version, downloadUrl } = useLatestRelease();
  return (
    <section id="download" className="plate plate-download" aria-labelledby="download-title">
      <PlateImage />
      <div className="frame">
        <div className="slab reveal">
          <span className="label">12 · Download</span>
          <h2 id="download-title" className="title">Get NotchTune.</h2>
          <p className="lede">Download the disk image, drag NotchTune to Applications, and look up.</p>
          <a className="btn btn-solid" href={downloadUrl}>
            <DownloadIcon aria-hidden="true" strokeWidth={2.2} />
            Download NotchTune {version}
          </a>
          <p className="slab-meta">macOS 14 or later · Apple Silicon · Free · <a href="https://github.com/dw2lam/NotchTune/releases">All releases</a></p>
          <div className="install">
            <p>This early-access build isn’t signed yet, so macOS may say NotchTune is damaged the first time you open it. Run this once in Terminal, then open it again:</p>
            <code>xattr -dr com.apple.quarantine "/Applications/NotchTune.app"</code>
          </div>
        </div>
      </div>
    </section>
  );
}
