import { REPO_URL } from '../hooks/useLatestRelease';

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
            <a href={REPO_URL}>GitHub</a>
            <a href={`${REPO_URL}/releases`}>Changelog</a>
            <a href={`${REPO_URL}/issues`}>Contact</a>
            <a href={`${REPO_URL}/blob/main/PRIVACY_POLICY.md`}>Privacy</a>
          </nav>
        </div>
      </div>
    </footer>
  );
}
