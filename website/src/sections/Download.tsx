import { useLatestRelease } from '../hooks/useLatestRelease';

export default function Download() {
  const { version, downloadUrl } = useLatestRelease();
  return (
    <section id="download" className="download band-light" aria-labelledby="download-title">
      <div className="frame">
        <div className="reveal">
          <h2 id="download-title" className="h2">Get NotchTune.</h2>
          <p className="lede">Free for macOS 14 or later on Apple Silicon. It works with Claude Code, Codex, Gemini CLI and six more agents, and with Spotify and Apple Music.</p>
          <p className="cta">
            <a className="btn" href={downloadUrl}>Download NotchTune {version}</a>
            <a className="more" href="https://github.com/dw2lam/NotchTune/releases">All releases</a>
          </p>
          <p className="fine">No accounts and no telemetry; everything stays on your Mac. It comes with 32 original sounds and updates itself through Sparkle.</p>
          <div className="install">
            <p>This early build isn’t signed yet. If macOS says NotchTune is damaged, run this once in Terminal, then open it again:</p>
            <code>xattr -dr com.apple.quarantine "/Applications/NotchTune.app"</code>
          </div>
        </div>
      </div>
    </section>
  );
}
