import { useEffect, useRef, useState } from 'react';
import './Demo.css';
import {
  IslandPanel, MusicTab, AgentsTab, ApprovalCard, ClosedPill,
  type IslandTab, type MockTrack, type MockSession, UsageChip,
} from '../mock';

/* ============================================================
   Live demo — a full interactive mock of the app, 1:1 with the
   real notch UI. Hover the pill to open, switch tabs, play the
   fake player, trigger an approval, pick a character.
   ============================================================ */

const TRACKS: MockTrack[] = [
  { title: 'Sienna', artist: 'The Marías', art: 'url(/assets/submarine.jpg)', duration: 218 },
  { title: 'Neon Cathedral', artist: 'Night Drive Collective', art: 'linear-gradient(135deg,#5b3df5,#c26bff 55%,#ff9ac2)', duration: 187 },
  { title: 'Golden Hour Static', artist: 'Fieldnotes', art: 'linear-gradient(135deg,#d9a441,#e86b3a 60%,#7c2d12)', duration: 243 },
];

const BASE_SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'api', branch: 'feat/bridge-queue',
    prompt: 'make BridgeServer dispatch on a background queue…',
    agent: 'claude', terminal: 'Ghostty', age: '‹1m',
    command: 'swift test --filter BridgeServerTests',
    subagents: [{ name: 'subagent', desc: 'searching the codebase', time: '3s' }],
  },
  {
    state: 'done', title: 'infra', branch: 'main',
    prompt: 'deploy the staging build',
    agent: 'codex', terminal: 'tmux', age: '2m',
  },
];

const CHARS = ['dino', 'ghost', 'crab', 'duck', 'claude'] as const;

export default function Demo() {
  const [open, setOpen] = useState(false);
  const [pinned, setPinned] = useState(false);
  const [tab, setTab] = useState<IslandTab>('music');
  const [trackIdx, setTrackIdx] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [position, setPosition] = useState(64);
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState(false);
  const [char, setChar] = useState<(typeof CHARS)[number]>('dino');
  const [glass, setGlass] = useState<'clear' | 'frosted' | 'off'>('clear');
  const [tint, setTint] = useState(22); /* app default tintStrength (LiquidGlass.swift:44) */
  const [approval, setApproval] = useState(false);
  const [notifMode, setNotifMode] = useState(true);
  const [resolved, setResolved] = useState<'allowed' | 'denied' | null>(null);
  const closeTimer = useRef<number>();

  const track = TRACKS[trackIdx];

  /* playback clock */
  useEffect(() => {
    if (!playing) return;
    const id = window.setInterval(() => {
      setPosition((p) => {
        if (p + 1 >= track.duration) {
          setTrackIdx((i) => (i + 1) % TRACKS.length);
          return 0;
        }
        return p + 1;
      });
    }, 1000);
    return () => window.clearInterval(id);
  }, [playing, track.duration]);

  const next = () => { setTrackIdx((i) => (i + 1) % TRACKS.length); setPosition(0); };
  const prev = () => { setTrackIdx((i) => (i + TRACKS.length - 1) % TRACKS.length); setPosition(0); };

  const enter = () => { window.clearTimeout(closeTimer.current); setOpen(true); };
  const leave = () => {
    if (pinned) return;
    closeTimer.current = window.setTimeout(() => setOpen(false), 350);
  };

  const triggerApproval = () => {
    setResolved(null);
    setApproval(true);
    setNotifMode(true);
    setTab('agents');
    setOpen(true);
    setPinned(true);
  };
  const resolve = (kind: 'allowed' | 'denied') => {
    setApproval(false);
    setResolved(kind);
    window.setTimeout(() => setResolved(null), 4000);
  };

  const approvalSession: MockSession = {
    state: 'approve', title: 'web', branch: 'main', prompt: 'ship the landing page',
    waiting: 'Waiting 0m 12s', agent: 'claude', terminal: 'WezTerm', age: '12s',
  };
  const sessions: MockSession[] = [
    ...(resolved
      ? [{ state: resolved === 'allowed' ? 'running' : 'idle', title: 'web', branch: 'main', prompt: 'ship the landing page', agent: 'claude', terminal: 'WezTerm', age: '‹1m', command: resolved === 'allowed' ? 'git push origin main' : undefined } as MockSession]
      : []),
    ...BASE_SESSIONS,
  ];

  const pillMode = approval
    ? { kind: 'agents' as const, char, running: true, tiles: [{ color: '#f4a4a4', state: 'waiting' as const }, { color: '#6ea7ff', state: 'running' as const }] }
    : playing
      ? { kind: 'music-compact' as const, art: track.art.startsWith('url') ? track.art.slice(4, -1) : '', playing }
      : { kind: 'idle' as const, char };

  return (
    <section id="demo" className="section">
      <div className="section-head reveal">
        <h2>Take it for a spin.</h2>
        <p>This is a live, pixel-faithful mock of the real app — same fonts, same spacing, same glass. Hover (or tap) the notch to open it.</p>
      </div>

      <div
        className="demo-scene reveal"
        data-open={open}
        onClick={(e) => {
          if (!(e.target as HTMLElement).closest('.demo-anchor')) { setPinned(false); setOpen(false); }
        }}
      >
        <div className="demo-menubar" />
        <div
          className="demo-anchor"
          onMouseEnter={enter}
          onMouseLeave={leave}
          onClick={() => { setOpen(true); setPinned(true); }}
        >
          <div className="demo-pill">
            {pillMode.kind === 'music-compact' && !pillMode.art ? (
              <ClosedPill layout="notch" mode={{ kind: 'agents', char, running: false, label: 'Claude Code' }} />
            ) : (
              <ClosedPill layout="notch" mode={pillMode} />
            )}
          </div>
          <div className="demo-panel" onClick={(e) => e.stopPropagation()}>
            <IslandPanel
              usage={<UsageChip name="Claude" window="5h" pct={41} />}
              tab={tab}
              onTab={setTab}
              glass={glass}
              tintStrength={tint / 100}
              ambientArt={tab === 'music' && playing && track.art.startsWith('url') ? track.art.slice(4, -1) : undefined}
              showNotchGap
            >
              {tab === 'music' ? (
                <MusicTab
                  track={track} playing={playing} position={position}
                  shuffle={shuffle} repeat={repeat}
                  onPlayPause={() => setPlaying((p) => !p)}
                  onPrev={prev} onNext={next}
                  onShuffle={() => setShuffle((s) => !s)}
                  onRepeat={() => setRepeat((r) => !r)}
                  onSeek={setPosition}
                />
              ) : approval && notifMode ? (
                /* notification presentation: only the actionable session +
                   card + "Show all N" (like the real app) */
                <AgentsTab sessions={[approvalSession]}>
                  <ApprovalCard
                    command="git push origin main"
                    path="~/dev/web"
                    onDeny={() => resolve('denied')}
                    onAllowOnce={() => resolve('allowed')}
                    onAlwaysAllow={() => resolve('allowed')}
                  />
                  <button type="button" className="nt-showall" onClick={() => setNotifMode(false)}>
                    Show all {BASE_SESSIONS.length + 1} sessions
                  </button>
                </AgentsTab>
              ) : (
                <AgentsTab sessions={approval ? [approvalSession, ...sessions] : sessions}>
                  {approval && (
                    <ApprovalCard
                      command="git push origin main"
                      path="~/dev/web"
                      onDeny={() => resolve('denied')}
                      onAllowOnce={() => resolve('allowed')}
                      onAlwaysAllow={() => resolve('allowed')}
                    />
                  )}
                </AgentsTab>
              )}
            </IslandPanel>
          </div>
          <div className="demo-hw-notch" aria-hidden="true" />
        </div>
      </div>

      <div className="demo-controls reveal">
        <div className="demo-ctl">
          <span className="demo-ctl-label">Try</span>
          <button type="button" className="demo-chip demo-chip-cta" onClick={triggerApproval}>
            Trigger an approval
          </button>
        </div>
        <div className="demo-ctl">
          <span className="demo-ctl-label">Character</span>
          {CHARS.map((c) => (
            <button
              type="button" key={c}
              className={`demo-chip ${char === c ? 'is-on' : ''}`}
              onClick={() => setChar(c)}
            >
              {c}
            </button>
          ))}
        </div>
        <div className="demo-ctl">
          <span className="demo-ctl-label">Glass</span>
          {(['clear', 'frosted', 'off'] as const).map((g) => (
            <button
              type="button" key={g}
              className={`demo-chip ${glass === g ? 'is-on' : ''}`}
              onClick={() => setGlass(g)}
            >
              {g === 'off' ? 'solid ink' : g}
            </button>
          ))}
        </div>
        <div className="demo-ctl">
          <span className="demo-ctl-label">Tint</span>
          <input
            type="range" min={0} max={100} step={1}
            value={tint}
            onChange={(e) => setTint(Number(e.target.value))}
            className="demo-slider"
            disabled={glass === 'off'}
            aria-label="Glass tint strength"
          />
          <span className="demo-pct">{tint}%</span>
        </div>
      </div>
    </section>
  );
}
