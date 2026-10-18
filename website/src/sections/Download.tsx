import { Download as DownloadIcon } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';

const SPEC: [string, string][] = [
  ['Coding agents', '9'],
  ['Terminals to jump back to', '7'],
  ['Original sounds', '32'],
  ['Accounts or telemetry', 'None'],
  ['License', 'GPL'],
  ['Updates', 'Sparkle'],
];

export default function Download() {
  const { version, downloadUrl } = useLatestRelease();
  return (
    <section id="download" className="sec sec-download" aria-labelledby="download-title">
      <div className="frame">
        <p className="bar"><span>07</span>Download</p>
        <div className="dl-body">
          <span className="sec-index" aria-hidden="true">07</span>
          <div className="slab dl reveal">
            <div className="dl-main">
              <img className="dl-icon" src="/assets/icon.png" alt="" width={72} height={72} loading="lazy" decoding="async" />
              <h2 id="download-title" className="h2">Get NotchTune.</h2>
              <p className="sub">Free, for macOS 14 or later on Apple Silicon.</p>
              <a className="btn btn-primary" href={downloadUrl}>
                <DownloadIcon aria-hidden="true" strokeWidth={2.2} />
                Download {version}
              </a>
              <p className="dl-meta"><a href="https://github.com/dw2lam/NotchTune/releases">All releases</a></p>
            </div>
            <div className="dl-side">
              <dl className="spec">
                {SPEC.map(([k, v]) => <div key={k}><dt>{k}</dt><dd>{v}</dd></div>)}
              </dl>
              <div className="well">
                <p>This early build isn’t signed yet. If macOS says NotchTune is damaged, run this once in Terminal, then open it again:</p>
                <code>xattr -dr com.apple.quarantine "/Applications/NotchTune.app"</code>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
