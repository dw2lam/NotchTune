import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import { usePhone } from '../hooks/useMedia';
import { IslandPanel, AgentsTab, UsageCycler, type MockSession } from '../mock';
import { USAGE_PROVIDERS, MODEL_WEEKLY } from '../lib/demoData';
import { Shot } from '../components/Shot';

const SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'notchtune · Show what the agent is doing in the pill',
    prompt: 'widen the wings while an agent works, timer on the right',
    activity: 'Editing IslandLiveActivity.swift',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  { state: 'approve', title: 'api · Cut the 2.2 release', waiting: 'Waiting 0m 12s', agent: 'codex', terminal: 'iTerm2', age: '12s' },
  {
    state: 'done', title: 'site · Put the new home page live',
    summary: 'Done. The new home page is live.',
    agent: 'gemini', terminal: 'tmux', age: '3m',
  },
];

export default function Hero() {
  const { version, downloadUrl } = useLatestRelease();
  const phone = usePhone();
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="frame">
        <p className="bar hero-bar">
          <span>01</span>
          NotchTune {version}
          <em>macOS 14 or later · Apple Silicon · Free</em>
        </p>
        <div className="hero-body">
          <h1 id="hero-title" className="h1 reveal">The calm at the top of your screen.</h1>
          <div className="hero-side reveal">
            <p className="sub">Your AI coding agents and your music, quietly in the notch.</p>
            <div className="cta">
              <a className="btn btn-primary" href={downloadUrl}>
                <Download aria-hidden="true" strokeWidth={2.2} />
                Download
              </a>
              <a className="btn btn-glass" href="https://github.com/dw2lam/NotchTune">GitHub</a>
            </div>
          </div>
        </div>
        <div className="slab hero-slab reveal">
          <p className="menubar" aria-hidden="true">
            <span><b>NotchTune</b><i>File</i><i>Edit</i><i>View</i><i>Window</i></span>
            <span>Sat 18 Oct 21:25</span>
          </p>
          <div className="hang">
            <Shot label="The opened NotchTune island: Claude editing a file, Codex waiting for approval and Gemini finished, with Claude usage in the header.">
              <IslandPanel usage={<UsageCycler providers={USAGE_PROVIDERS} />} modelWeekly={MODEL_WEEKLY} tab="agents" glass="off" showNotchGap={!phone}>
                <AgentsTab sessions={SESSIONS} total={9} />
              </IslandPanel>
            </Shot>
          </div>
        </div>
      </div>
    </section>
  );
}
