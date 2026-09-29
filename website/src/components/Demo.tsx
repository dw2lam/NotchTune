import { useCallback, useEffect, useRef, useState } from 'react';
import './Demo.css';
import {
  IslandPanel, MusicTab, AgentsTab, ApprovalCard, QuestionCard, CompletionToast,
  NotificationSessionHeader, ShowAll, ClosedPill, UsageCycler,
  MyspaceTab, RemindersTab, MyspaceDropTarget, AGENT_TINTS,
  type IslandTab, type MockTrack, type MockSession, type LiveActivity, type PillMode,
  type MockThought, type MockReminder,
} from '../mock';
import { USAGE_PROVIDERS, MODEL_WEEKLY } from '../lib/demoData';

/* ============================================================
   Live demo — a full interactive mock of the app, 1:1 with the
   real notch UI. The closed pill carries a live activity while an
   agent works; hover (0.4s dwell) or click to open — the surface
   grows out of the pill as one shape and tucks back into the
   hardware notch before the wings re-emerge. Trigger an approval,
   a question or a completion toast, swipe to skip, pick a buddy.
   ============================================================ */

const TRACKS: MockTrack[] = [
  { title: 'Sienna', artist: 'The Marías', art: 'url(/assets/submarine.jpg)', duration: 218 },
  { title: 'Neon Cathedral', artist: 'Night Drive Collective', art: 'linear-gradient(135deg,#5b3df5,#c26bff 55%,#ff9ac2)', duration: 187 },
  { title: 'Golden Hour Static', artist: 'Fieldnotes', art: 'linear-gradient(135deg,#d9a441,#e86b3a 60%,#7c2d12)', duration: 243 },
];

const BASE_SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'api · Make BridgeServer dispatch on a background queue',
    prompt: 'make BridgeServer dispatch on a background queue',
    activity: 'Running swift test --filter BridgeServerTests',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  {
    state: 'done', title: 'research · Summarize the autoresearch paper',
    summary: 'Done. I pulled out the key differences that matter for our loop.',
    agent: 'codex', terminal: 'Ghostty', age: '3m',
  },
  { state: 'idle', title: 'infra · Deploy the staging build', agent: 'codex', terminal: 'tmux', age: '27m' },
  { state: 'idle', title: 'voice-input · Look at the voice-input repo', agent: 'claude', terminal: 'Ghostty', age: '1h' },
];

const COMPLETIONS = [
  {
    agent: 'codex', workspace: 'research', prompt: 'Read the autoresearch paper and compare it to our loop.',
    excerpt: 'Done. I pulled out the key differences: their loop scores every candidate against a held-out eval before it commits, and it keeps a ranked memory of failed attempts so it never retries them.',
  },
  {
    agent: 'claude', workspace: 'site', prompt: 'Swap the hero to the new session rows.',
    excerpt: 'The hero now renders the new session rows and the usage cycler. Build passes and nothing else changed.',
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

type Surface = 'tabs' | 'approval' | 'question' | 'toast';
/* closed → opening (pill-sized clip, 1 frame) → open → tucking (into the
   hardware notch) → closed (wings re-emerge) */
type Phase = 'closed' | 'opening' | 'open' | 'tucking';

const HOVER_DWELL = 400; /* HoverOpenMode default 0.4s */
const CLOSE_MS = 400;    /* closeAnimationDuration */

export default function Demo() {
  const [phase, setPhase] = useState<Phase>('closed');
  const [emerge, setEmerge] = useState(0);
  const [pinned, setPinned] = useState(false);
  const [surface, setSurface] = useState<Surface>('tabs');
  const [tab, setTab] = useState<IslandTab>('agents');
  const [trackIdx, setTrackIdx] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [position, setPosition] = useState(64);
  const [shuffle, setShuffle] = useState(false);
  const [repeat, setRepeat] = useState(false);
  const [char, setChar] = useState<(typeof CHARS)[number]>('dino');
  const [colorByAgent, setColorByAgent] = useState(false);
  const [agentsWorking, setAgentsWorking] = useState(true);
  const [glass, setGlass] = useState<'clear' | 'frosted' | 'off'>('clear');
  const [tint, setTint] = useState(22); /* app default tintStrength (LiquidGlass.swift:44) */
  const [thoughts, setThoughts] = useState<MockThought[]>(BASE_THOUGHTS);
  const [reminders, setReminders] = useState<MockReminder[]>(BASE_REMINDERS);
  const [skip, setSkip] = useState<'next' | 'prev' | null>(null);
  const [toastIdx, setToastIdx] = useState(0);
  /* approval flow: the pill says what the web session needs / does */
  const [webState, setWebState] = useState<'none' | 'approval' | 'question' | 'running' | 'finished' | 'idle'>('none');
  const [webSince, setWebSince] = useState(0);
  /* file-drag demo: idle → hint (near the notch) → catch (over it) */
  const [dragPhase, setDragPhase] = useState<'idle' | 'hint' | 'catch'>('idle');
  const sceneRef = useRef<HTMLDivElement>(null);
  const pillRef = useRef<HTMLDivElement>(null);
  const dwellTimer = useRef<number>();
  const closeTimer = useRef<number>();
  const toastTimer = useRef<number>();
  const skipTimer = useRef<number>();
  const lastSkip = useRef(0);
  const hoveringPanel = useRef(false);
  const workingSince = useRef(Date.now() - 42_000);

  const track = TRACKS[trackIdx];
  const artUrl = track.art.startsWith('url') ? track.art.slice(4, -1) : undefined;
  const isOpen = phase === 'opening' || phase === 'open';

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

  /* ---- open / close morph ---- */
  const measurePill = () => {
    const scene = sceneRef.current;
    const pill = pillRef.current?.querySelector<HTMLElement>('.nt-pill');
    if (!scene || !pill) return;
    const shift = parseFloat(pill.style.getPropertyValue('--notch-shift')) || 0;
    scene.style.setProperty('--pw', `${pill.offsetWidth}px`);
    scene.style.setProperty('--ps', `${shift}px`);
  };

  const open = useCallback((nextSurface?: Surface) => {
    window.clearTimeout(closeTimer.current);
    window.clearTimeout(dwellTimer.current);
    if (nextSurface) setSurface(nextSurface);
    setPhase((p) => {
      if (p === 'open' || p === 'opening') return p;
      measurePill();
      requestAnimationFrame(() => requestAnimationFrame(() => setPhase((q) => (q === 'opening' ? 'open' : q))));
      return 'opening';
    });
  }, []);

  const close = useCallback(() => {
    window.clearTimeout(dwellTimer.current);
    window.clearTimeout(toastTimer.current);
    setPinned(false);
    setPhase((p) => {
      if (p === 'closed' || p === 'tucking') return p;
      window.clearTimeout(closeTimer.current);
      closeTimer.current = window.setTimeout(() => {
        setPhase('closed');
        setSurface('tabs');
        setEmerge((n) => n + 1);
      }, CLOSE_MS + 30); /* wingsEmergeDelay */
      return 'tucking';
    });
  }, []);

  const enter = () => {
    window.clearTimeout(closeTimer.current);
    if (isOpen) return;
    window.clearTimeout(dwellTimer.current);
    dwellTimer.current = window.setTimeout(() => open(), HOVER_DWELL);
  };
  const leave = () => {
    window.clearTimeout(dwellTimer.current);
    if (pinned || !isOpen) return;
    closeTimer.current = window.setTimeout(close, 350);
  };

  /* ---- swipe to skip (two-finger horizontal swipe over the pill) ---- */
  const doSkip = (dir: 'next' | 'prev') => {
    lastSkip.current = Date.now();
    if (dir === 'next') next(); else prev();
    setSkip(dir);
    window.clearTimeout(skipTimer.current);
    skipTimer.current = window.setTimeout(() => setSkip(null), 1100);
  };
  const onWheel = (e: React.WheelEvent) => {
    if (isOpen) return;
    if (Math.abs(e.deltaX) < 18 || Math.abs(e.deltaX) < Math.abs(e.deltaY) * 1.5) return;
    if (Date.now() - lastSkip.current < 700) return; /* one skip per gesture */
    doSkip(e.deltaX > 0 ? 'next' : 'prev');
  };

  /* ---- notifications ---- */
  const triggerApproval = () => {
    setWebState('approval');
    setWebSince(Date.now());
    setPinned(true);
    open('approval');
  };
  const triggerQuestion = () => {
    setWebState('question');
    setWebSince(Date.now());
    setPinned(true);
    open('question');
  };
  const scheduleToastCollapse = () => {
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => {
      if (!hoveringPanel.current) close();
    }, 6000); /* toasts auto-collapse after 6s unless hovered */
  };
  const triggerCompletion = () => {
    setToastIdx(0);
    setPinned(false);
    open('toast');
    scheduleToastCollapse();
  };
  const resolve = (kind: 'allowed' | 'denied' | 'answered') => {
    close();
    if (kind === 'denied') { setWebState('idle'); return; }
    setWebState('running');
    setWebSince(Date.now());
    window.setTimeout(() => {
      setWebState((s) => (s === 'running' ? 'finished' : s));
      window.setTimeout(() => setWebState((s) => (s === 'finished' ? 'idle' : s)), 4000); /* finishedPeekDuration */
    }, 4500);
  };

  /* keyboard: ⌘Y / ⌘N on the approval card, ⏎ / Esc on toasts */
  useEffect(() => {
    if (phase !== 'open' || surface === 'tabs') return;
    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey;
      if (e.key === 'Escape') { close(); return; }
      if (surface === 'approval' && mod && (e.key === 'y' || e.key === 'n')) {
        e.preventDefault();
        resolve(e.key === 'y' ? 'allowed' : 'denied');
      } else if (surface === 'toast' && e.key === 'Enter') {
        close();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, surface]);

  useEffect(() => () => {
    [dwellTimer, closeTimer, toastTimer, skipTimer].forEach((t) => window.clearTimeout(t.current));
  }, []);

  /* ---- file drag ---- */
  const onSceneDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    const scene = sceneRef.current;
    if (!scene) return;
    const r = scene.getBoundingClientRect();
    const dx = Math.abs(e.clientX - (r.left + r.width / 2));
    const dy = e.clientY - r.top;
    if (dx < 110 && dy < 64) setDragPhase('catch');
    else if (dx < 240 && dy < 170) setDragPhase('hint');
    else setDragPhase('idle');
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
      setPinned(true);
      open('tabs');
    }
    setDragPhase('idle');
  };

  /* ---- closed pill: IslandLiveActivity.resolve priority ---- */
  const liveMusicArt = playing ? artUrl : undefined;
  let activity: LiveActivity | null = null;
  let activityAgent = 'claude';
  if (webState === 'approval') {
    activity = { kind: 'approval', title: 'Claude needs approval', subtitle: 'git push origin main', since: webSince };
  } else if (webState === 'question') {
    activity = { kind: 'answer', title: 'Claude has a question', subtitle: 'Which auth method?', since: webSince };
  } else if (webState === 'finished') {
    activity = { kind: 'finished', title: 'Claude finished', subtitle: 'web' };
  } else if (webState === 'running') {
    activity = { kind: 'working', title: 'Claude · web', subtitle: 'Running git push origin main', since: webSince, musicArt: liveMusicArt, others: agentsWorking ? 1 : 0 };
  } else if (agentsWorking) {
    activity = { kind: 'working', title: 'Claude · api', subtitle: 'Running swift test', since: workingSince.current, musicArt: liveMusicArt };
  }
  if (activity?.kind === 'approval' || activity?.kind === 'answer') activityAgent = 'claude';
  const agentTint = colorByAgent ? AGENT_TINTS[activityAgent] : undefined;

  const pillMode: PillMode = activity
    ? { kind: 'live', char, activity, tint: agentTint }
    : artUrl && (playing || position > 0)
      ? { kind: 'music-compact', art: artUrl, playing }
      : { kind: 'idle', char, tint: agentTint };

  /* ---- opened content ---- */
  const webSession: MockSession | null =
    webState === 'running' ? { state: 'running', title: 'web · Ship the landing page', prompt: 'ship the landing page', activity: 'Running git push origin main', agent: 'claude', terminal: 'WezTerm', age: '<1m' }
      : webState === 'approval' || webState === 'question'
        ? { state: webState === 'approval' ? 'approve' : 'answer', title: 'web · Ship the landing page', waiting: 'Waiting 0m 12s', agent: 'claude', terminal: 'WezTerm', age: '12s' }
        : webState === 'finished' || webState === 'idle'
          ? { state: 'done', title: 'web · Ship the landing page', summary: 'Pushed main. The deploy is building.', agent: 'claude', terminal: 'WezTerm', age: '1m' }
          : null;
  const sessions: MockSession[] = [
    ...(webSession ? [webSession] : []),
    ...BASE_SESSIONS.map((s, i) => (i === 0 && !agentsWorking ? { ...s, state: 'done' as const, summary: 'All BridgeServer tests pass on the background queue.', prompt: undefined, activity: undefined } : s)),
  ];
  const total = sessions.length + 5;
  const toast = COMPLETIONS[toastIdx % COMPLETIONS.length];

  const notificationMode = surface !== 'tabs';
  const panelContent = (() => {
    if (surface === 'approval') {
      return (
        <>
          <NotificationSessionHeader title="web · Ship the landing page" prompt="ship the landing page" agent="claude" terminal="WezTerm" age="12s" />
          <ApprovalCard
            command="git push origin main"
            path="~/dev/web"
            onDeny={() => resolve('denied')}
            onAllow={() => resolve('allowed')}
          />
          <ShowAll count={total} onClick={() => { setSurface('tabs'); setTab('agents'); }} />
        </>
      );
    }
    if (surface === 'question') {
      return (
        <>
          <NotificationSessionHeader title="web · Add sign-in to the dashboard" prompt="How should we approach it?" agent="claude" terminal="WezTerm" age="<1m" />
          <QuestionCard
            question="Which authentication method should we use?"
            options={[
              { label: 'Passkeys', desc: 'WebAuthn, no passwords' },
              { label: 'Session cookies', desc: 'Traditional approach' },
              { label: 'OAuth 2.0', desc: 'Third-party sign-in' },
            ]}
            onSubmit={() => resolve('answered')}
          />
          <ShowAll count={total} onClick={() => { setSurface('tabs'); setTab('agents'); }} />
        </>
      );
    }
    if (surface === 'toast') {
      return (
        <CompletionToast
          agent={toast.agent} workspace={toast.workspace} prompt={toast.prompt} excerpt={toast.excerpt}
          total={total}
          queue={{ index: toastIdx % COMPLETIONS.length, count: COMPLETIONS.length }}
          onRotate={(fwd) => { setToastIdx((i) => (i + (fwd ? 1 : COMPLETIONS.length - 1)) % COMPLETIONS.length); scheduleToastCollapse(); }}
          onJump={close}
          onReply={close}
          onShowAll={() => { window.clearTimeout(toastTimer.current); setPinned(true); setSurface('tabs'); setTab('agents'); }}
        />
      );
    }
    switch (tab) {
      case 'myspace':
        return (
          <MyspaceTab
            thoughts={thoughts}
            onSubmit={(text) => setThoughts((t) => [{ text, time: new Date().toLocaleTimeString() }, ...t])}
            onDelete={(i) => setThoughts((t) => t.filter((_, idx) => idx !== i))}
          />
        );
      case 'reminders':
        return (
          <RemindersTab
            reminders={reminders}
            onToggle={(i) => setReminders((r) => r.map((item, idx) => (idx === i ? { ...item, done: !item.done } : item)))}
          />
        );
      case 'music':
        return (
          <MusicTab
            track={track} playing={playing} position={position}
            shuffle={shuffle} repeat={repeat}
            onPlayPause={() => setPlaying((p) => !p)}
            onPrev={prev} onNext={next}
            onShuffle={() => setShuffle((s) => !s)}
            onRepeat={() => setRepeat((r) => !r)}
            onSeek={setPosition}
          />
        );
      default:
        return <AgentsTab sessions={sessions} total={total} />;
    }
  })();

  return (
    <section id="demo" className="section">
      <div className="section-head reveal">
        <h2>Take it for a spin.</h2>
        <p>This is a live, pixel-faithful mock of the real app — same fonts, same spacing, same glass. The pill is already tracking an agent; hover (or tap) the notch to open it, or swipe sideways over it to skip a track.</p>
      </div>

      <div
        ref={sceneRef}
        className="demo-scene reveal"
        data-phase={phase}
        data-surface={surface}
        data-catching={dragPhase === 'catch'}
        onClick={(e) => {
          if (!(e.target as HTMLElement).closest('.demo-anchor')) close();
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
          onWheel={onWheel}
          onClick={() => { setPinned(true); open(); }}
        >
          {dragPhase === 'hint' && (
            <div className="demo-drop-hint">
              <svg viewBox="0 0 24 24"><path d="M12 2a1 1 0 011 1v6.59l2.3-2.3 1.4 1.42L12 13.4 7.3 8.7l1.4-1.41L11 9.6V3a1 1 0 011-1zM3 13h4.2l1.2 2.4h7.2L16.8 13H21a1 1 0 011 1v6a2 2 0 01-2 2H4a2 2 0 01-2-2v-6a1 1 0 011-1z" /></svg>
              Drop to hold
            </div>
          )}
          <div ref={pillRef} className={`demo-pill ${dragPhase === 'hint' ? 'is-hinting' : ''}`} key={`pill-${emerge}`} data-emerge={emerge > 0}>
            <ClosedPill
              layout="notch"
              mode={pillMode}
              skip={skip}
              onArtClick={pillMode.kind === 'music-compact' ? () => { window.clearTimeout(dwellTimer.current); setPlaying((p) => !p); } : undefined}
            />
          </div>
          {dragPhase === 'catch' && (
            <div className="demo-drop-panel">
              <div className="nt nt-island nt-plainglass">
                <MyspaceDropTarget />
              </div>
            </div>
          )}
          <div
            className="demo-panel"
            onClick={(e) => { e.stopPropagation(); if (surface === 'toast') { window.clearTimeout(toastTimer.current); } }}
            onMouseEnter={() => { hoveringPanel.current = true; }}
            onMouseLeave={() => { hoveringPanel.current = false; if (surface === 'toast' && phase === 'open') scheduleToastCollapse(); }}
            style={dragPhase === 'catch' ? { opacity: 0 } : undefined}
          >
            <IslandPanel
              usage={<UsageCycler providers={USAGE_PROVIDERS} />}
              modelWeekly={MODEL_WEEKLY}
              tab={notificationMode ? undefined : tab}
              onTab={setTab}
              glass={glass}
              tintStrength={tint / 100}
              ambientArt={!notificationMode && tab === 'music' && playing ? artUrl : undefined}
              divider={notificationMode && surface !== 'toast'}
              showNotchGap
            >
              <div key={surface}>{panelContent}</div>
            </IslandPanel>
          </div>
          <div className="demo-hw-notch" aria-hidden="true" />
        </div>
      </div>

      <div className="demo-controls reveal">
        <div className="demo-ctl">
          <span className="demo-ctl-label">Try</span>
          <button type="button" className="demo-chip demo-chip-cta" onClick={triggerApproval}>Trigger an approval</button>
          <button type="button" className="demo-chip demo-chip-q" onClick={triggerQuestion}>Ask a question</button>
          <button type="button" className="demo-chip demo-chip-done" onClick={triggerCompletion}>Finish a task</button>
          <button type="button" className="demo-chip" onClick={() => doSkip('next')}>Swipe to skip ⏩</button>
        </div>
        <div className="demo-ctl">
          <span
            className="demo-file"
            draggable
            onDragStart={(e) => e.dataTransfer.setData('text/plain', 'quarterly-report.pdf')}
            onDragEnd={() => setDragPhase('idle')}
          >📄 quarterly-report.pdf — drag me at the notch</span>
        </div>
        <div className="demo-ctl">
          <span className="demo-ctl-label">Agents</span>
          <button type="button" className={`demo-chip ${agentsWorking ? 'is-on' : ''}`} onClick={() => setAgentsWorking(true)}>Working</button>
          <button type="button" className={`demo-chip ${!agentsWorking ? 'is-on' : ''}`} onClick={() => setAgentsWorking(false)}>Idle · music</button>
        </div>
        <div className="demo-ctl">
          <span className="demo-ctl-label">Character</span>
          {CHARS.map((c) => (
            <button type="button" key={c} className={`demo-chip ${char === c ? 'is-on' : ''}`} onClick={() => setChar(c)}>{c}</button>
          ))}
          <button type="button" className={`demo-chip ${colorByAgent ? 'is-on' : ''}`} onClick={() => setColorByAgent((v) => !v)}>Color by agent</button>
        </div>
        <div className="demo-ctl">
          <span className="demo-ctl-label">Glass</span>
          {(['clear', 'frosted', 'off'] as const).map((g) => (
            <button type="button" key={g} className={`demo-chip ${glass === g ? 'is-on' : ''}`} onClick={() => setGlass(g)}>
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
      <p className="demo-hint reveal">On the approval card, <kbd>⌘Y</kbd> allows and <kbd>⌘N</kbd> denies. <kbd>Esc</kbd> dismisses.</p>
    </section>
  );
}
