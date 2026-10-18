import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import { IslandPanel, AgentsTab, UsageCycler, type MockSession } from '../mock';
import { USAGE_PROVIDERS, MODEL_WEEKLY } from '../lib/demoData';
import { Fit } from '../components/Fit';
import { Shot } from '../components/Shot';
import { Screen } from '../components/Screen';

const SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'notchtune · Show what the agent is doing in the pill',
    prompt: 'widen the wings while an agent works, timer on the right',
    activity: 'Editing IslandLiveActivity.swift',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  { state: 'approve', title: 'api · Cut the 2.2 release', waiting: 'Waiting 0m 12s', agent: 'codex', terminal: 'iTerm2', age: '12s' },
  {
    state: 'done', title: 'site · Put the hero on frosted glass',
    summary: 'Done. The hero now floats on glass over the night sky.',
    agent: 'claude', terminal: 'tmux', age: '3m',
  },
  { state: 'idle', title: 'infra · Deploy the staging build', agent: 'codex', terminal: 'Ghostty', age: '1h' },
];

export default function Hero() {
  const { version, downloadUrl } = useLatestRelease();
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="wrap">
        <div className="hero-pill glass-soft reveal"><i aria-hidden="true" /> NotchTune {version} is here</div>
        <h1 id="hero-title" className="h1 reveal d1">The calm at the top<br /><span>of your screen.</span></h1>
        <p className="lede reveal d2">
          NotchTune is a calm notch companion for your AI coding agents and your music on macOS.
          Glance up to see what they’re doing, answer when they need you, and get back to work.
        </p>
        <div className="hero-actions reveal d2">
          <a className="btn btn-primary" href={downloadUrl}>
            <Download aria-hidden="true" strokeWidth={2.2} />
            Download for macOS
          </a>
          <a className="btn btn-ghost" href="https://github.com/dw2lam/NotchTune">View on GitHub</a>
        </div>
        <p className="hero-meta reveal d2">Version {version} · macOS 14 or later · Apple Silicon · Free and open source</p>

        <div className="hero-shot stage glass reveal">
          <Shot label="The opened NotchTune island hanging from the notch: Claude editing a file, Codex waiting for approval, a finished task and an idle session, with Claude usage in the header.">
            <Fit width={1000}>
              <Screen height={452}>
                <IslandPanel usage={<UsageCycler providers={USAGE_PROVIDERS} />} modelWeekly={MODEL_WEEKLY} tab="agents" glass="off">
                  <AgentsTab sessions={SESSIONS} total={9} />
                </IslandPanel>
              </Screen>
            </Fit>
          </Shot>
        </div>
      </div>
    </section>
  );
}
