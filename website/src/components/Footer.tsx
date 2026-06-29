export default function Footer() {
  return (
    <footer className="footer">
      <div className="footer-inner reveal">
        <div className="f-brand">
          <img src="/assets/icon.png" alt="" />
          <div>
            <div className="f-name">NotchTune</div>
            <div className="f-tag">Music + AI agents, in your notch.</div>
          </div>
        </div>
        <div className="credits">
          <h5>Standing on good shoulders</h5>
          <p>NotchTune is built on the work of people who got here first:</p>
          <ul>
            <li><a href="https://github.com/martinfekete10/Tuneful" target="_blank" rel="noopener">Tuneful</a> by <a href="https://github.com/martinfekete10" target="_blank" rel="noopener">Martin Fekete</a> — native macOS playback controls &amp; interface ideas.</li>
            <li><a href="https://github.com/Octane0411" target="_blank" rel="noopener">Octane0411</a> — the dynamic-notch integration &amp; terminal-native AI tracking foundations behind Open Island.</li>
          </ul>
        </div>
        <div className="f-links">
          <a href="https://github.com/dw2lam/NotchTune" target="_blank" rel="noopener">GitHub</a>
          <a href="https://github.com/dw2lam/NotchTune/releases" target="_blank" rel="noopener">Releases</a>
          <a href="https://github.com/dw2lam/NotchTune/blob/main/PRIVACY_POLICY.md" target="_blank" rel="noopener">Privacy</a>
        </div>
      </div>
      <div className="footer-base">Local-first &amp; open source · macOS 14+ · © 2026 David Lam</div>
    </footer>
  );
}
