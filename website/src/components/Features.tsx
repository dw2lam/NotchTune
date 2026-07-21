import { useState } from 'react';
import { MusicTab, AgentsTab, ApprovalCard, ClosedPill, TourCoach, type MockSession } from '../mock';

/* Feature highlights — each stage crops in on the one fragment of the
   island the feature is about, rendered with the 1:1 mock kit. */

const AGENT_ROWS: MockSession[] = [
  {
    state: 'running', title: 'api', branch: 'feat/bridge-queue',
    prompt: 'make BridgeServer dispatch on a background queue…',
    agent: 'claude', terminal: 'Ghostty', age: '‹1m',
    subagents: [{ name: 'subagent', desc: 'searching the codebase', time: '3s' }],
  },
  {
    state: 'answer', title: 'web', branch: 'main',
    prompt: 'redesign the pricing page',
    waiting: 'Waiting 0m 18s',
    agent: 'gemini', terminal: 'WezTerm', age: '18s',
  },
  {
    state: 'done', title: 'infra', branch: 'main',
    prompt: 'deploy the staging build',
    agent: 'codex', terminal: 'tmux', age: '2m',
  },
];

export default function Features() {
  const [playing, setPlaying] = useState(true);
  const [position, setPosition] = useState(102);

  return (
    <section id="features" className="section">
      <div className="section-head reveal">
        <h2>One island. Every moment that matters.</h2>
        <p>NotchTune switches itself between music and agents, so the notch always shows the thing you need right now.</p>
      </div>

      {/* Music — close-up on the player itself */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Music</span>
          <h3>Full playback, right in the glass.</h3>
          <p>Control Spotify or Apple Music without leaving your work — artwork that flips with the track, a scrubbable progress rail, shuffle and repeat, all inside the liquid-glass panel that lives where your eyes already are.</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/purple.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ transform: 'scale(1.08)' }}>
              <MusicTab
                track={{ title: 'Sienna', artist: 'The Marías', art: 'url(/assets/submarine.jpg)', duration: 218 }}
                playing={playing}
                position={position}
                onPlayPause={() => setPlaying((p) => !p)}
                onSeek={setPosition}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Agents — close-up on the session rows */}
      <div className="feature feature-rev reveal">
        <div className="feature-text">
          <span className="kicker">Agents</span>
          <h3>Every state, at a glance.</h3>
          <p>Watch your terminal-native coding agents live. The status dot tells you exactly where each one is — before you've even switched windows.</p>
          <div className="states-legend">
            <span><span className="s-dot running" /> Working</span>
            <span><span className="s-dot waiting" /> Waiting on you</span>
            <span><span className="s-dot done" /> Done</span>
          </div>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/green.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(470px, 100%)', transform: 'scale(1.04)' }}>
              <AgentsTab sessions={AGENT_ROWS} />
            </div>
          </div>
        </div>
      </div>

      {/* Approvals — close-up on the permission card */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Approvals &amp; questions</span>
          <h3>Say yes without breaking flow.</h3>
          <p>When an agent needs permission or has a question, the island grows into a notification panel right under the notch. Approve, deny, or answer in place — then it round-trips straight back to the process that asked.</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/orange.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(440px, 100%)', transform: 'scale(1.1)' }}>
              <ApprovalCard
                command="rm -rf ./build && swift build -c release"
                path="~/dev/api"
              />
            </div>
          </div>
        </div>
      </div>

      {/* secondary grid */}
      <div className="grid3 reveal">
        <article className="card glass">
          <div className="card-ico">🔔</div>
          <h4>Quiet by default</h4>
          <p>Configurable system sounds for permission and completion events — or mute it entirely. English and 简体中文 built in.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">↩︎</div>
          <h4>Jump back to the right window</h4>
          <p>One click returns focus to the exact terminal — Ghostty, iTerm2, WezTerm, tmux, Terminal.app, cmux, and more.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">🖥️</div>
          <h4>Follows your focus</h4>
          <p>The island moves to whatever display you're working on, and adapts as it goes — a real notch surface on MacBooks, a clean top-center bar on external and non-notch screens. It even keeps a separate look for each.</p>
        </article>
      </div>
      {/* Onboarding — the guided tour runs in the real notch */}
      <div className="feature feature-rev reveal">
        <div className="feature-text">
          <span className="kicker">Onboarding</span>
          <h3>A tour that happens in your actual notch.</h3>
          <p>
            Setup is a short wizard — connect your agents, pick a music player,
            style the island live on your real notch — then it hands you over to
            a hands-on tour: a demo agent asks for approval, you resolve it, peek
            the music tab, and drop a file into Myspace. Sixty seconds, nothing
            fake left behind. Replay it anytime from Settings.
          </p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage nt-stage-col" style={{ backgroundImage: 'url(/assets/wallpapers/sonoma.jpg)' }}>
            <ClosedPill layout="notch" mode={{ kind: 'agents', char: 'dino', running: true, tiles: [{ color: '#f4a4a4', state: 'waiting' }] }} />
            <TourCoach
              icon="cursor"
              tint="#6ea7ff"
              text="A demo agent needs your approval — hover the notch to open the island."
            />
          </div>
        </div>
      </div>
    </section>
  );
}
