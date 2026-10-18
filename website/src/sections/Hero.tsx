import { useLatestRelease } from '../hooks/useLatestRelease';
import { Shot } from '../components/Shot';
import { Crop } from '../components/Feature';

export default function Hero() {
  const { downloadUrl } = useLatestRelease();
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="hero-shot">
        <Crop>
          <Shot
            name="island" eager
            alt="The NotchTune island opened from the notch: usage limits at the top, then four agent sessions. Claude is running swift test in api, Codex fixed the checkout button in web, Claude wrote the release notes in docs, and Codex renamed the color tokens in design-system."
          />
        </Crop>
      </div>
      <div className="frame hero-copy">
        <h1 id="hero-title" className="h1 reveal">The calm at the top of your screen.</h1>
        <div className="hero-side reveal">
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
