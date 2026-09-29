import { useEffect, useRef, useState } from 'react';
import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import { IslandPanel, AgentsTab, UsageCycler, type MockSession } from '../mock';
import { USAGE_PROVIDERS, MODEL_WEEKLY } from '../lib/demoData';

const HERO_SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'notchtune · Make the pill show what the agent is doing',
    prompt: 'widen the wings while an agent works, timer on the right',
    activity: 'Editing IslandLiveActivity.swift',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  {
    state: 'approve', title: 'api · Cut the 2.2 release',
    waiting: 'Waiting 0m 12s',
    agent: 'codex', terminal: 'iTerm2', age: '12s',
  },
  {
    state: 'done', title: 'site · Build the liquid-glass hero',
    summary: 'Done. The hero now uses the new session rows and usage cycler.',
    agent: 'claude', terminal: 'tmux', age: '3m',
  },
  {
    state: 'idle', title: 'infra · Deploy the staging build',
    agent: 'codex', terminal: 'Ghostty', age: '1h',
  },
];

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
          NotchTune turns your Mac's notch into a live control surface for your terminal
          AI agents and your music. Watch an agent work right in the closed notch, approve
          it from the keyboard, and jump back to the right session in one click.{' '}
          <em>Native, local-first, no account.</em>
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
          <IslandPanel
            usage={<UsageCycler providers={USAGE_PROVIDERS} />}
            modelWeekly={MODEL_WEEKLY}
            tab="agents"
            glass="clear"
            showNotchGap={false}
          >
            <AgentsTab sessions={HERO_SESSIONS} />
          </IslandPanel>
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
