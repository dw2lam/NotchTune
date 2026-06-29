import { useEffect, useRef, useState } from 'react';
import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import { IslandTop, TabBar, UsageChip } from './IslandParts';

const BRANDS = [
  { name: 'Claude Code', file: 'claude.svg' },
  { name: 'Codex', file: 'openai.svg' },
  { name: 'OpenCode', file: 'opencode.svg' },
  { name: 'Gemini', file: 'googlegemini.svg' },
  { name: 'Kimi', file: 'kimi.svg' },
  { name: 'Qwen', file: 'qwen.svg' },
  { name: 'Spotify', file: 'spotify.svg' },
  { name: 'Apple Music', file: 'applemusic.svg', am: true },
];

const TRACK = (
  <>
    {BRANDS.map((b) => (
      <img
        key={b.name}
        className={`logo${b.am ? ' logo-am' : ''}`}
        src={`/assets/logos/${b.file}`}
        alt={b.name}
        title={b.name}
      />
    ))}
  </>
);

export default function Hero() {
  const { version, downloadUrl } = useLatestRelease();
  const [mounted, setMounted] = useState(false);
  const demoRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  const fade = (extra = '') => `nt-fade${extra}${mounted ? ' in' : ''}`;

  return (
    <section className="hero">
      <div className={`hero-copy ${fade()}`}>
        <div className="eyebrow"><span className="dot-live" /> v<span>{version}</span> · Free &amp; open source</div>
        <h1 className="nt-hero-head">
          Your notch,<br />
          <span className="nt-hero-accent">finally useful.</span>
        </h1>
        <p className="lede">
          NotchTune turns your Mac's notch into a live control surface — music and your
          terminal AI agents in one place. Playback, approvals, and one-tap jump-back
          to the right session. <em>Native, local-first, no account.</em>
        </p>
      </div>

      <div className={`hero-cta ${fade(' d3')}`}>
        <div className="hero-actions">
          <a className="nt-cta" href={downloadUrl} target="_blank" rel="noopener">
            <Download size={16} strokeWidth={2} />
            <span>Download v{version} for macOS</span>
          </a>
          <a className="nt-cta-ghost" href="https://github.com/dw2lam/NotchTune" target="_blank" rel="noopener">
            View source
          </a>
        </div>
        <div className="hero-meta">macOS 14+ · Apple Silicon &amp; Intel · No account, no telemetry</div>
      </div>

      <div className="hero-stage reveal" ref={demoRef}>
        <div className="scene scene-hero">
          <div className="island island-expanded glass-deep">
            <IslandTop>
              <UsageChip name="Claude" time="5h" pct="41%" />
              <UsageChip name="Codex" time="7d" pct="76%" tone="u-warn" />
            </IslandTop>
            <TabBar active="agents" />
            <ul className="rows">
              <li className="row">
                <span className="rdot on" />
                <div className="rmain">
                  <div className="rtitle"><b>notchtune</b> · wiring antigravity hooks</div>
                  <div className="rprev"><span className="who">You:</span> the notch should react when agy is actually working…</div>
                  <div className="rstate">running</div>
                </div>
                <div className="rmeta"><div className="rbadges"><span className="rb">Claude Code</span><span className="rb">Ghostty</span></div><span className="rtime">‹1m</span></div>
              </li>
              <li className="row">
                <span className="rdot wait" />
                <div className="rmain">
                  <div className="rtitle"><b>island-demo</b> · run the release script?</div>
                  <div className="rstate">waiting for approval</div>
                </div>
                <div className="rmeta"><div className="rbadges"><span className="rb">Codex</span><span className="rb">iTerm2</span></div><span className="rtime">12s</span></div>
              </li>
              <li className="row">
                <span className="rdot done" />
                <div className="rmain"><div className="rtitle"><b>site</b> · built the liquid-glass hero</div></div>
                <div className="rmeta"><div className="rbadges"><span className="rb">Claude Code</span><span className="rb">tmux</span></div><span className="rtime">3m</span></div>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <div className="strip reveal">
        <span className="strip-label">Works with</span>
        <div className="marquee" aria-label="Works with Claude Code, Codex, Gemini, Kimi, OpenCode, Factory, Qwen, Spotify, and Apple Music">
          <div className="marquee-track" aria-hidden="true">
            {TRACK}
            {TRACK}
          </div>
        </div>
      </div>
    </section>
  );
}
