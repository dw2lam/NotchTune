import { useState } from 'react';
import {
  MusicTab, AgentsTab, ApprovalCard, CompletionToast, NotificationSessionHeader, ClosedPill,
  UsageCycler, type MockSession,
} from '../mock';
import { USAGE_PROVIDERS } from '../lib/demoData';

/* Feature highlights — each stage crops in on the one fragment of the
   island the feature is about, rendered with the 1:1 mock kit. */

const AGENT_ROWS: MockSession[] = [
  {
    state: 'running', title: 'api · Make BridgeServer dispatch on a queue',
    prompt: 'make BridgeServer dispatch on a background queue',
    activity: 'Running swift test',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  {
    state: 'answer', title: 'web · Redesign the pricing page',
    waiting: 'Waiting 0m 18s',
    agent: 'gemini', terminal: 'WezTerm', age: '18s',
  },
  {
    state: 'done', title: 'infra · Deploy the staging build',
    summary: 'Staging is live. Two migrations ran cleanly.',
    agent: 'codex', terminal: 'tmux', age: '2m',
  },
  {
    state: 'idle', title: 'docs · Tidy the README',
    agent: 'claude', terminal: 'Ghostty', age: '1h',
  },
];

const SINCE = Date.now() - 42_000;

export default function Features() {
  const [playing, setPlaying] = useState(true);
  const [position, setPosition] = useState(102);

  return (
    <section id="features" className="section">
      <div className="section-head reveal">
        <h2>One island. Every moment that matters.</h2>
        <p>NotchTune switches itself between agents and music, so the notch always shows the thing you need right now — and stays out of the way the rest of the time.</p>
      </div>

      {/* Live activity — the closed pill itself */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Live activity</span>
          <h3>Watch it work without opening anything.</h3>
          <p>While an agent works, the pill's wings widen to show which agent, which project, and what it's doing right now, with a turn timer on the right. When it needs you, the title turns to the waiting color and the timer counts how long it's been waiting. When it finishes, you get a quick green check, and then it tucks away.</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage live-stage" style={{ backgroundImage: 'url(/assets/wallpapers/sonoma.jpg)' }}>
            <div className="live-stack">
              <div className="live-bar">
                <ClosedPill layout="notch" alignNotch={false} mode={{ kind: 'live', char: 'dino', activity: { kind: 'working', title: 'Codex · api', subtitle: 'Running swift test', since: SINCE, musicArt: '/assets/submarine.jpg' } }} />
              </div>
              <div className="live-bar">
                <ClosedPill layout="notch" alignNotch={false} mode={{ kind: 'live', char: 'dino', activity: { kind: 'approval', title: 'Codex needs approval', subtitle: 'git push origin main', timer: '0:21' } }} />
              </div>
              <div className="live-bar">
                <ClosedPill layout="notch" alignNotch={false} mode={{ kind: 'live', char: 'dino', activity: { kind: 'finished', title: 'Codex finished', subtitle: 'api' } }} />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Completion toast */}
      <div className="feature feature-rev reveal">
        <div className="feature-text">
          <span className="kicker">Completions</span>
          <h3>Small toasts. Far fewer bumps.</h3>
          <p>A finished turn arrives as a small toast that never takes more than a fifth of your screen: who finished, what you asked, and a three-line excerpt of the reply. You can jump to the terminal or reply right there. Bursts of events settle into a single bump, and nothing pops up at all if you're already looking at that agent's terminal.</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/purple.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(480px, 100%)' }}>
              <CompletionToast
                agent="codex" workspace="open-island"
                prompt="Go ahead and rebuild DEV into a debug page."
                excerpt="The debug page is in. It lists every hook event with its payload, and a replay button re-sends one to the island. The plan file is written. Are your hooks firing?"
                queue={{ index: 0, count: 2 }}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Agents — close-up on the session rows */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Agents</span>
          <h3>Every session on one line.</h3>
          <p>Each row is one line: a status dot, the task, and flat tags for the agent, the terminal, and how long ago it last moved. Running rows add what you asked and what the agent is doing right now. Click anywhere on a row to jump straight to that terminal.</p>
          <div className="states-legend">
            <span><span className="s-dot running" /> Working</span>
            <span><span className="s-dot waiting" /> Needs approval</span>
            <span><span className="s-dot question" /> Has a question</span>
            <span><span className="s-dot done" /> Done</span>
          </div>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/green.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(500px, 100%)', padding: '8px 0 2px' }}>
              <AgentsTab sessions={AGENT_ROWS} total={9} />
            </div>
          </div>
        </div>
      </div>

      {/* Approvals — close-up on the permission card */}
      <div className="feature feature-rev reveal">
        <div className="feature-text">
          <span className="kicker">Approvals &amp; questions</span>
          <h3>Say yes without leaving the keyboard.</h3>
          <p>When an agent needs permission or has a question, a card drops out of the notch. Press <kbd className="kbd">⌘Y</kbd> to allow or <kbd className="kbd">⌘N</kbd> to deny, and pick answers with <kbd className="kbd">⌘1</kbd>–<kbd className="kbd">⌘9</kbd>. Your answer goes straight back to the process that asked.</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/orange.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(460px, 100%)', padding: 0 }}>
              <NotificationSessionHeader title="api · Rebuild the release bundle" prompt="clean build before we tag" agent="claude" terminal="Ghostty" age="<1m" />
              <ApprovalCard command="rm -rf ./build && swift build -c release" path="~/dev/api" />
            </div>
          </div>
        </div>
      </div>

      {/* Music — close-up on the player + the closed-notch controls */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Music</span>
          <h3>Full playback, even with the notch closed.</h3>
          <p>Control Spotify or Apple Music without leaving your work. Swipe sideways over the closed pill to skip a track. Click its artwork to play or pause. Open it for the full player: artwork that flips with the track, a scrubbable progress bar, shuffle, and repeat.</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage music-stage" style={{ backgroundImage: 'url(/assets/wallpapers/purple.jpg)' }}>
            <div className="live-bar live-bar-solo">
              <ClosedPill layout="notch" alignNotch={false} skip="next" mode={{ kind: 'music-compact', art: '/assets/submarine.jpg', playing }} onArtClick={() => setPlaying((p) => !p)} />
            </div>
            <div className="nt-fragment nt-zoom">
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

      {/* secondary grid */}
      <div className="grid3 reveal">
        <article className="card glass">
          <div className="card-ico card-ico-usage"><span className="nt"><UsageCycler providers={USAGE_PROVIDERS} showsResets={false} /></span></div>
          <h4>Usage at a glance</h4>
          <p>Your Claude, Codex, and Gemini limits in the header, one provider at a time. Click to cycle. Each limit shows when it resets ("4h43m", "1d5h"), and weekly per-model caps sit on the right.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">⌘</div>
          <h4>Keyboard first</h4>
          <p><kbd className="kbd">⌘Y</kbd> allows, <kbd className="kbd">⌘N</kbd> denies, and <kbd className="kbd">⇧⌘Y</kbd> always allows. <kbd className="kbd">⏎</kbd> jumps to the terminal, <kbd className="kbd">⌘R</kbd> replies, <kbd className="kbd">⌘[</kbd> <kbd className="kbd">⌘]</kbd> flip between toasts, and <kbd className="kbd">Esc</kbd> dismisses.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">🎨</div>
          <h4>Color by agent</h4>
          <p>Claude in orange, Codex in blue, Gemini in green. Agent tags use each brand's color, and your island buddy can wear the color of whichever agent is working.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">🫧</div>
          <h4>Liquid Glass, and smoother motion</h4>
          <p>Buttons, tabs, and header controls are native macOS 26 Liquid Glass. The panel grows out of the pill as one shape, and when it closes it tucks back into the notch before the wings come out again.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">↩︎</div>
          <h4>Jump back to the right window</h4>
          <p>One click returns focus to the exact terminal — Ghostty, iTerm2, WezTerm, tmux, Terminal.app, cmux, and more.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">🖥️</div>
          <h4>Follows your focus</h4>
          <p>The island moves to whichever display you're working on. It's a real notch surface on MacBooks and a clean top-center bar on other screens. Compact density slims the pill to fit a 24pt menu bar.</p>
        </article>
      </div>
    </section>
  );
}
