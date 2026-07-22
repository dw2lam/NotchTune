import { useEffect, useRef, useState } from 'react';
import './Demo.css';
import {
  IslandPanel, MusicTab, AgentsTab, ApprovalCard, ClosedPill,
  MyspaceTab, RemindersTab, MyspaceDropTarget,
  type IslandTab, type MockTrack, type MockSession,
  type MockThought, type MockReminder, UsageChip,
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

const BASE_THOUGHTS: MockThought[] = [
  {
    text: 'final installer art',
    time: '4:12:08 PM',
    attachments: [{ name: 'dmg-background@2x.png', ext: 'png', kind: 'image', art: 'linear-gradient(135deg,#2c1e4f,#7a3aa2 55%,#e88b5a)' }],
  },
  { text: 'ship the notch update tonight', time: '2:03:41 PM', reminderAt: 'Jul 21, 9:00 AM' },
];

const BASE_REMINDERS: MockReminder[] = [
  { text: 'Reply to the App Store review', reminderAt: 'Jul 21, 9:30 AM', created: '4:02:11 PM' },
  { text: 'Water the monstera', created: '1:38:52 PM' },
  { text: 'Send the beta build to Sam', reminderAt: 'Jul 20, 5:00 PM', created: '11:14:27 AM', done: true },
];

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
  const [thoughts, setThoughts] = useState<MockThought[]>(BASE_THOUGHTS);
  const [reminders, setReminders] = useState<MockReminder[]>(BASE_REMINDERS);
  /* file-drag demo: idle → hint (near the notch) → catch (over it) */
  const [dragPhase, setDragPhase] = useState<'idle' | 'hint' | 'catch'>('idle');
  const sceneRef = useRef<HTMLDivElement>(null);
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

  const onSceneDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    const scene = sceneRef.current;
    if (!scene) return;
    const r = scene.getBoundingClientRect();
    const dx = Math.abs(e.clientX - (r.left + r.width / 2));
    const dy = e.clientY - r.top;
    if (dx < 110 && dy < 64) {
      setDragPhase('catch');
    } else if (dx < 240 && dy < 170) {
      setDragPhase('hint');
    } else {
      setDragPhase('idle');
    }
  };

  const onSceneDrop = (e: React.DragEvent) => {
    e.preventDefault();
    if (dragPhase !== 'idle') {
      setThoughts((t) => [{
        text: '',
        time: new Date().toLocaleTimeString(),
        attachments: [{ name: 'quarterly-report.pdf', ext: 'pdf', kind: 'pdf' as const }],
      }, ...t]);
      setTab('myspace');
      setOpen(true);
      setPinned(true);
    }
    setDragPhase('idle');
  };

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
        ref={sceneRef}
        className="demo-scene reveal"
        data-open={open}
        data-catching={dragPhase === 'catch'}
        onClick={(e) => {
          if (!(e.target as HTMLElement).closest('.demo-anchor')) { setPinned(false); setOpen(false); }
        }}
        onDragOver={onSceneDragOver}
        onDragLeave={() => setDragPhase('idle')}
        onDrop={onSceneDrop}
      >
        <div className="demo-menubar" />
        <div
          className="demo-anchor"
          onMouseEnter={enter}
          onMouseLeave={leave}
          onClick={() => { setOpen(true); setPinned(true); }}
        >
          {dragPhase === 'hint' && (
            <div className="demo-drop-hint">
              <svg viewBox="0 0 24 24"><path d="M12 2a1 1 0 011 1v6.59l2.3-2.3 1.4 1.42L12 13.4 7.3 8.7l1.4-1.41L11 9.6V3a1 1 0 011-1zM3 13h4.2l1.2 2.4h7.2L16.8 13H21a1 1 0 011 1v6a2 2 0 01-2 2H4a2 2 0 01-2-2v-6a1 1 0 011-1z" /></svg>
              Drop to hold
            </div>
          )}
          <div className={`demo-pill ${dragPhase === 'hint' ? 'is-hinting' : ''}`}>
            {pillMode.kind === 'music-compact' && !pillMode.art ? (
              <ClosedPill layout="notch" mode={{ kind: 'agents', char, running: false, label: 'Claude Code' }} />
            ) : (
              <ClosedPill layout="notch" mode={pillMode} />
            )}
          </div>
          {dragPhase === 'catch' && (
            <div className="demo-panel demo-drop-panel">
              <div className="nt nt-island nt-plainglass">
                <MyspaceDropTarget />
              </div>
            </div>
          )}
          <div className="demo-panel" onClick={(e) => e.stopPropagation()} style={dragPhase === 'catch' ? { opacity: 0 } : undefined}>
            <IslandPanel
              usage={<><UsageChip name="Claude" window="5h" pct={41} /><UsageChip name="Codex" window="5h" pct={78} /></>}
              tab={tab}
              onTab={setTab}
              glass={glass}
              tintStrength={tint / 100}
              ambientArt={tab === 'music' && playing && track.art.startsWith('url') ? track.art.slice(4, -1) : undefined}
              showNotchGap
            >
              {tab === 'myspace' ? (
                <MyspaceTab
                  thoughts={thoughts}
                  onSubmit={(text) => setThoughts((t) => [
                    { text, time: new Date().toLocaleTimeString() }, ...t,
                  ])}
                  onDelete={(i) => setThoughts((t) => t.filter((_, idx) => idx !== i))}
                />
              ) : tab === 'reminders' ? (
                <RemindersTab
                  reminders={reminders}
                  onToggle={(i) => setReminders((r) => r.map(
                    (item, idx) => (idx === i ? { ...item, done: !item.done } : item),
                  ))}
                />
              ) : tab === 'music' ? (
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
          <span
            className="demo-file"
            draggable
            onDragStart={(e) => e.dataTransfer.setData('text/plain', 'quarterly-report.pdf')}
            onDragEnd={() => setDragPhase('idle')}
          >📄 quarterly-report.pdf — drag me at the notch</span>
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
