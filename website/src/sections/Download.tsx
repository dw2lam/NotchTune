import { DOWNLOAD_URL, REPO_URL, useLatestRelease } from '../hooks/useLatestRelease';

export default function Download() {
  const version = useLatestRelease();
  return (
    <section id="download" className="download band-light" aria-labelledby="download-title">
      <div className="frame">
        <div className="reveal">
          <h2 id="download-title" className="h2">Get NotchTune.</h2>
          <p className="lede">Free for macOS 14 or later on Apple Silicon. It works with 11 agents, including Claude Code, Codex, Cursor and Antigravity, and with Spotify and Apple Music.</p>
          <p className="cta">
            <a className="btn" href={DOWNLOAD_URL}>Download NotchTune{version ? ` ${version}` : ''}</a>
            <a className="more" href={`${REPO_URL}/releases`}>All releases</a>
          </p>
          <div className="install">
            <h3>First launch</h3>
            <ol>
              <li>Open the disk image and drag NotchTune to Applications.</li>
              <li>Open it. NotchTune is signed but not notarized yet, so macOS will block it.</li>
              <li>Go to System Settings &gt; Privacy &amp; Security and click Open Anyway. Right-click Open no longer works on macOS 15 and later.</li>
            </ol>
            <p>Or run this once in Terminal, then open it:</p>
            <code>xattr -dr com.apple.quarantine "/Applications/NotchTune.app"</code>
          </div>
          <dl className="specs">
            <dt>Displays</dt>
            <dd>In the notch, or as a bar at the top centre on Macs without one and on external displays.</dd>
            <dt>Agents</dt>
            <dd>Claude Code, Codex, OpenCode, Gemini CLI, Kimi CLI, Cursor, Antigravity, Qoder, Qwen Code, Factory and CodeBuddy. A Setup doctor checks each connection.</dd>
            <dt>Terminals</dt>
            <dd>Terminal, iTerm2, Ghostty, cmux, Kaku, WezTerm, Warp and tmux.</dd>
            <dt>Sounds</dt>
            <dd>32 originals, built in.</dd>
            <dt>Updates</dt>
            <dd>They download in the background. Click Update to restart into the new version.</dd>
            <dt>Privacy</dt>
            <dd>No account and no telemetry. Agent data, notes, calendars and the camera stay on your Mac. NotchTune only goes online to check GitHub for updates and to look up Spotify artwork and links.</dd>
          </dl>
        </div>
      </div>
    </section>
  );
}
