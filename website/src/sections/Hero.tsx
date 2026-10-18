import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import { usePhone } from '../hooks/useMedia';
import { IslandPanel, AgentsTab, UsageCycler, ClosedPill, type MockSession } from '../mock';
import { USAGE_PROVIDERS, MODEL_WEEKLY } from '../lib/demoData';
import { Shot } from '../components/Shot';
import { PlateImage } from '../components/Plate';

const SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'notchtune · Show what the agent is doing in the pill',
    prompt: 'widen the wings while an agent works, timer on the right',
    activity: 'Editing IslandLiveActivity.swift',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  { state: 'approve', title: 'api · Cut the 2.2 release', waiting: 'Waiting 0m 12s', agent: 'codex', terminal: 'iTerm2', age: '12s' },
  {
    state: 'done', title: 'site · Put the oasis on the home page',
    summary: 'Done. Edited 4 files, and the build passes.',
    agent: 'claude', terminal: 'tmux', age: '3m',
  },
];

export default function Hero() {
  const { version, downloadUrl } = useLatestRelease();
  const phone = usePhone();
  return (
    <section className="hero" aria-labelledby="hero-title">
      <div className="frame">
        <div className="hero-meta">
          <span className="label">01</span>
          <span className="label">NotchTune {version} for macOS</span>
          <span className="label">Agents · Music · Meetings</span>
        </div>
        <h1 id="hero-title" className="mega">The calm at the top<br /><em>of your screen.</em></h1>
        <div className="hero-row">
          <p className="lede">
            NotchTune is a calm notch companion for your AI coding agents and your music on macOS.
            Glance up to see what they’re doing, answer when they need you, and get back to work.
          </p>
          <div>
            <div className="hero-actions">
              <a className="btn btn-solid" href={downloadUrl}>
                <Download aria-hidden="true" strokeWidth={2.2} />
                Download for macOS
              </a>
              <a className="btn btn-line" href="https://github.com/dw2lam/NotchTune">View on GitHub</a>
            </div>
            <p className="hero-small">Version {version} · macOS 14 or later · Apple Silicon · Free and open source</p>
          </div>
        </div>
      </div>

      <div className="plate plate-hero">
        <PlateImage eager sizes="(max-width: 599px) 980px, (max-width: 1023px) 1900px, 100vw" />
        <div className={`plate-hang${phone ? ' is-pill' : ''}`}>
          {phone ? (
            <Shot label="The closed notch: Claude is running swift test in api, 3 minutes 12 seconds in.">
              <div className="zoom-pill">
                <ClosedPill layout="pill" mode={{ kind: 'live', char: 'dino', activity: { kind: 'working', title: 'Claude · api', subtitle: 'Running swift test', timer: '3:12' } }} />
              </div>
            </Shot>
          ) : (
            <Shot label="The opened NotchTune island hanging from the top of the screen: Claude editing a file, Codex waiting for approval and a finished task, with Claude usage in the header.">
              <div className="zoom-hero">
                <IslandPanel usage={<UsageCycler providers={USAGE_PROVIDERS} />} modelWeekly={MODEL_WEEKLY} tab="agents" glass="off">
                  <AgentsTab sessions={SESSIONS} total={9} />
                </IslandPanel>
              </div>
            </Shot>
          )}
        </div>
        <p className="plate-cap"><b>Fig. 01</b>{phone ? 'The closed notch, mid-task.' : 'The island, opened over a moonlit oasis.'}</p>
      </div>
    </section>
  );
}
