const REPO = 'https://github.com/dw2lam/NotchTune';

export default function Footer() {
  return (
    <footer className="footer">
      <div className="frame footer-inner">
        <p className="footer-main">
          <a className="wordmark" href="#top">
            <img src="/assets/icon.png" alt="" width={20} height={20} loading="lazy" decoding="async" />
            NotchTune
          </a>
          <span>Free and open source under the GPL. © 2026 David Lam.</span>
        </p>
        <nav className="footer-links" aria-label="Project">
          <a href={REPO}>GitHub</a>
          <a href={`${REPO}/releases`}>Releases</a>
          <a href={`${REPO}/blob/main/PRIVACY_POLICY.md`}>Privacy</a>
        </nav>
        <p className="footer-credit">
          Built on <a href="https://github.com/Octane0411/open-vibe-island">Open Vibe Island</a> by Octane0411
          and <a href="https://github.com/martinfekete10/Tuneful">Tuneful</a> by Martin Fekete.
        </p>
      </div>
    </footer>
  );
}
