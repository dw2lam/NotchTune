import { useLatestRelease } from '../hooks/useLatestRelease';
import MacBook from '../components/MacBook';

export default function Hero() {
  const { downloadUrl } = useLatestRelease();
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="frame">
        <h1 id="hero-title" className="h1 hero-title">The calm at the top of your screen.</h1>
        <MacBook label="A MacBook Pro with NotchTune open under the notch: usage limits at the top, then four agent sessions. Claude is running swift test in api, Codex fixed the checkout button in web, Claude wrote the release notes in docs, and Codex renamed the color tokens in design-system.">
          <img className="mbp-pill" src="/assets/shots/pill-working.webp" width={468} height={38} alt="" />
          <img className="mbp-island" src="/assets/shots/island.webp" width={650} height={354} alt="" fetchPriority="high" />
        </MacBook>
        <div className="hero-copy">
          <p className="lede">NotchTune keeps your AI coding agents and your music in the notch, so you can stay in your work.</p>
          <p className="cta">
            <a className="btn" href={downloadUrl}>Download for Mac</a>
            <a className="more" href="https://github.com/dw2lam/NotchTune">View on GitHub</a>
          </p>
        </div>
      </div>
    </section>
  );
}
