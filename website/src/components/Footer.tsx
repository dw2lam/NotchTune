const REPO = 'https://github.com/dw2lam/NotchTune';

export default function Footer() {
  return (
    <footer className="footer">
      <div className="wrap footer-inner">
        <div>
          <a className="wordmark" href="#top">
            <img src="/assets/icon.png" alt="" width={24} height={24} />
            NotchTune
          </a>
          <p>A calm notch companion for AI coding agents and music on macOS. Free and open source under the GPL.</p>
        </div>
        <div>
          <p>
            Built on the shoulders of <a href="https://github.com/Octane0411/open-vibe-island">Open Vibe Island</a> by
            Octane0411 and <a href="https://github.com/martinfekete10/Tuneful">Tuneful</a> by Martin Fekete.
          </p>
          <p>© 2026 David Lam</p>
        </div>
        <nav className="footer-links" aria-label="Project">
          <a href={REPO}>GitHub</a>
          <a href={`${REPO}/releases`}>Releases</a>
          <a href={`${REPO}/blob/main/PRIVACY_POLICY.md`}>Privacy</a>
        </nav>
      </div>
    </footer>
  );
}
