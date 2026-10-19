const REPO = 'https://github.com/dw2lam/NotchTune';

export default function Footer() {
  return (
    <footer className="footer band-light">
      <div className="frame">
        <p>
          NotchTune is free and open source under the GPL. Built on{' '}
          <a href="https://github.com/Octane0411/open-vibe-island">Open Vibe Island</a> by Octane0411
          and <a href="https://github.com/martinfekete10/Tuneful">Tuneful</a> by Martin Fekete.
        </p>
        <div className="footer-row">
          <span>Copyright © 2026 David Lam.</span>
          <nav aria-label="Project">
            <a href={REPO}>GitHub</a>
            <a href={`${REPO}/releases`}>Releases</a>
            <a href={`${REPO}/blob/main/PRIVACY_POLICY.md`}>Privacy</a>
          </nav>
        </div>
      </div>
    </footer>
  );
}
