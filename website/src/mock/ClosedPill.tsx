import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import './mock.css';
import { SPRITES, SPRITES_RUN, spriteSVG } from '../lib/sprites';
import { PlayIcon, PauseIcon, CheckIcon } from './icons';

/* ============================================================
   1:1 closed pill (V6ClosedPillShape + V6NotchContent):
   flat top with an outward 6pt top curve ("ears",
   GrowingNotchShape.surfacePath, closedEarRadius 6), semicircular
   bottom (r = h/2). MacBook layout = asymmetric wings around the
   physical notch. Overflowing text uses the app's marquee —
   30px/s ping-pong with 1.1s pauses (V6NotchContent:407-436).
   ============================================================ */

export function Marquee({ text, className = '' }: { text: string; className?: string }) {
  const outer = useRef<HTMLSpanElement>(null);
  const inner = useRef<HTMLSpanElement>(null);
  const [scrolling, setScrolling] = useState(false);
  const [style, setStyle] = useState<CSSProperties>();

  useLayoutEffect(() => {
    const o = outer.current;
    const i = inner.current;
    if (!o || !i) return;
    const dist = i.scrollWidth - o.clientWidth;
    if (dist > 2) {
      /* scrollDuration = max(0.8, travel/30), pause 1.1s each end */
      const travel = Math.max(0.8, dist / 30);
      setScrolling(true);
      setStyle({
        '--marq-dist': `-${dist}px`,
        '--marq-dur': `${(travel + 1.1) * 2}s`,
      } as CSSProperties);
    } else {
      setScrolling(false);
      setStyle(undefined);
    }
  }, [text]);

  return (
    <span ref={outer} className={`nt-marq ${scrolling ? 'is-scrolling' : ''} ${className}`.trim()} style={style}>
      <span ref={inner} className="nt-marq-inner">{text}</span>
    </span>
  );
}

export function Waveform({ paused = false, color }: { paused?: boolean; color?: string }) {
  return (
    <span className={`nt-eq ${paused ? 'is-paused' : ''}`} style={color ? { color } : undefined}>
      <i /><i /><i /><i />
    </span>
  );
}

export function PixelSprite({ char, running = false, tint, hop = false }: {
  char: string; running?: boolean;
  /** "Color by agent": the character takes the agent's brand colour */
  tint?: string;
  /** one-shot hop (finished peek / nudge) */
  hop?: boolean;
}) {
  const grid = (running && SPRITES_RUN[char]) || SPRITES[char];
  if (!grid) return null;
  return (
    <span
      className={`nt-sprite ${running ? 'is-running' : ''} ${hop ? 'is-hopping' : ''}`.trim()}
      style={tint ? { color: tint } : undefined}
      role="img" aria-label={`${char} sprite`}
      dangerouslySetInnerHTML={{ __html: spriteSVG(grid) }}
    />
  );
}

/* balanced-rows agent grid (V6NotchContent:75-96) */
export function AgentGrid({ tiles }: { tiles: { color: string; state: 'running' | 'idle' | 'waiting' }[] }) {
  const cols = tiles.length <= 1 ? 1 : Math.ceil(tiles.length / Math.min(2, Math.ceil(tiles.length / 4)));
  return (
    <span className="nt-grid" style={{ gridTemplateColumns: `repeat(${Math.min(cols, 4)}, 8px)` }}>
      {tiles.map((t, i) => (
        <i key={i} className={t.state === 'idle' ? 'is-idle' : t.state === 'waiting' ? 'is-waiting' : ''} style={{ background: t.color }} />
      ))}
    </span>
  );
}

/** Turn timer "0:42" (IslandLiveActivity.elapsedText) — ticks every second. */
export function LiveTimer({ since, className = '' }: { since: number; className?: string }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);
  const s = Math.max(0, Math.floor((now - since) / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, '0');
  return <span className={`nt-live-timer ${className}`.trim()}>{h ? `${h}:${String(m).padStart(2, '0')}:${ss}` : `${m}:${ss}`}</span>;
}

/** Swipe-to-skip feedback (MusicSkipArrows): two play.fill triangles
    lighting up in turn on an eased sin² wave; ⏪ is ⏩ mirrored. */
export function SkipArrows({ direction }: { direction: 'next' | 'prev' }) {
  return (
    <span className={`nt-skip ${direction === 'prev' ? 'is-prev' : ''}`} aria-label={direction === 'next' ? 'Next track' : 'Previous track'}>
      <i><PlayIcon /></i><i><PlayIcon /></i>
    </span>
  );
}

export type LiveKind = 'working' | 'approval' | 'answer' | 'finished';

export interface LiveActivity {
  kind: LiveKind;
  /** "Codex · api" / "Codex needs approval" / "Codex finished" */
  title: string;
  /** "Running swift test" / the command / the question / the reply */
  subtitle?: string;
  /** epoch ms the timer counts from (working / waiting) */
  since?: number;
  /** static timer text instead of a ticking one */
  timer?: string;
  /** other live sessions ("+2") */
  others?: number;
  /** album-art chip beside the timer while music plays */
  musicArt?: string;
}

export type PillMode =
  | { kind: 'music-notification'; art: string; title: string; artist: string; playing: boolean; accent?: string }
  | { kind: 'music-compact'; art: string; playing: boolean; accent?: string }
  | { kind: 'agents'; char: string; running: boolean; label?: string; tiles?: { color: string; state: 'running' | 'idle' | 'waiting' }[]; tint?: string }
  | { kind: 'live'; char: string; activity: LiveActivity; tint?: string }
  | { kind: 'idle'; char: string; tint?: string };

function LiveTrailing({ a }: { a: LiveActivity }) {
  return (
    <span className="nt-live-trail">
      {a.musicArt && <span className="nt-live-chip" style={{ backgroundImage: `url(${a.musicArt})` }} aria-label="Now playing" />}
      {!!a.others && <span className="nt-live-others">+{a.others}</span>}
      {a.kind === 'finished' ? (
        <span className="nt-live-check"><CheckIcon /></span>
      ) : a.timer ? (
        <span className={`nt-live-timer nt-live-${a.kind}`}>{a.timer}</span>
      ) : a.since ? (
        <LiveTimer since={a.since} className={`nt-live-${a.kind}`} />
      ) : null}
    </span>
  );
}

export function ClosedPill({
  mode, glass = false, width, layout = 'pill', alignNotch = true, skip, onArtClick, children, className = '',
}: {
  /** MacBook layout: shift asymmetric wings so the gap stays centred */
  alignNotch?: boolean;
  mode: PillMode;
  glass?: boolean;
  /** optional fixed width; omit to auto-size like the real pill */
  width?: number;
  /** 'pill' = external top-bar pill · 'notch' = MacBook wings around the physical notch */
  layout?: 'pill' | 'notch';
  /** swipe-to-skip feedback drawn over the right wing */
  skip?: 'next' | 'prev' | null;
  /** closed music pill: a click on the art plays/pauses instead of opening */
  onArtClick?: () => void;
  children?: ReactNode;
  className?: string;
}) {
  let left: ReactNode = null;
  let right: ReactNode = null;
  const art = (src: string, playing?: boolean) => (
    <span
      className={`nt-pill-art ${onArtClick ? 'is-clickable' : ''}`}
      style={{ backgroundImage: `url(${src})` }}
      onClick={onArtClick ? (e) => { e.stopPropagation(); onArtClick(); } : undefined}
      role={onArtClick ? 'button' : undefined}
      aria-label={onArtClick ? (playing ? 'Pause' : 'Play') : undefined}
    >
      {playing === false && <span className="nt-pill-art-play"><PlayIcon /></span>}
    </span>
  );
  switch (mode.kind) {
    case 'music-notification':
      left = (
        <>
          {art(mode.art)}
          <span className="nt-pill-meta">
            <Marquee text={mode.title} className="nt-pill-title" />
            <Marquee text={mode.artist} className="nt-pill-artist" />
          </span>
        </>
      );
      right = (
        <span style={{ width: 18, height: 18, color: mode.accent ?? 'var(--nt-paper)', display: 'grid', placeItems: 'center', flex: 'none' }}>
          <span style={{ width: 10, height: 10, display: 'block' }}>
            {mode.playing ? <PauseIcon /> : <PlayIcon />}
          </span>
        </span>
      );
      break;
    case 'music-compact':
      left = art(mode.art, mode.playing);
      right = <Waveform paused={!mode.playing} color={mode.accent} />;
      break;
    case 'agents':
      left = (
        <>
          <PixelSprite char={mode.char} running={mode.running} tint={mode.tint} />
          {mode.label && <Marquee text={mode.label} className="nt-pill-label" />}
        </>
      );
      right = mode.tiles ? <AgentGrid tiles={mode.tiles} /> : <span style={{ width: 24, flex: 'none' }} />;
      break;
    case 'live': {
      const a = mode.activity;
      left = (
        <>
          <PixelSprite char={mode.char} running={a.kind === 'working'} tint={mode.tint} hop={a.kind === 'finished'} />
          {layout === 'notch' ? (
            <span className="nt-live-text" key={a.kind + a.title}>
              <b className={`nt-live-${a.kind}`}>{a.title}</b>
              {a.subtitle && <em>{a.subtitle}</em>}
            </span>
          ) : (
            <span className="nt-live-inline" key={a.kind + a.title}>
              <b className={`nt-live-${a.kind}`}>{a.title}</b>
              {a.subtitle && <em>{'  '}{a.subtitle}</em>}
            </span>
          )}
        </>
      );
      right = <LiveTrailing a={a} />;
      break;
    }
    case 'idle':
      left = <PixelSprite char={mode.char} tint={mode.tint} />;
      right = layout === 'notch' ? <span style={{ width: 24, flex: 'none' }} /> : null;
      break;
  }

  const pillRef = useRef<HTMLDivElement>(null);
  const [shift, setShift] = useState(0);
  /* keep the notch gap centred on the cutout (asymmetric wings) */
  useLayoutEffect(() => {
    const pill = pillRef.current;
    if (!pill || layout !== 'notch' || !alignNotch) return;
    const measure = () => {
      const gap = pill.querySelector<HTMLElement>('.nt-pill-notchgap');
      if (!gap) { setShift(0); return; }
      const pr = pill.getBoundingClientRect();
      const gr = gap.getBoundingClientRect();
      const scale = pr.width / (pill.offsetWidth || pr.width) || 1;
      const cur = (gr.left + gr.width / 2 - (pr.left + pr.width / 2)) / scale;
      setShift(Math.round(-cur * 2) / 2);
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(pill);
    return () => ro.disconnect();
  }, [layout, alignNotch, mode.kind]);

  const inner = children ?? (
    <>
      <span className="nt-wing nt-wing-l">{left}</span>
      {right && <span className={layout === 'notch' ? 'nt-pill-notchgap' : 'nt-pill-gap'} />}
      {right && <span className="nt-wing nt-wing-r">{right}</span>}
    </>
  );
  return (
    <div
      ref={pillRef}
      className={`nt nt-pill nt-pill-${mode.kind} nt-pill-layout-${layout} ${glass ? 'nt-glass' : ''} ${className}`.trim()}
      style={{ ...(width ? { width } : {}), ...(layout === 'notch' && alignNotch ? { ['--notch-shift' as string]: `${shift}px` } : {}) }}
    >
      <span className="nt-ear nt-ear-l" aria-hidden="true" />
      <span className="nt-ear nt-ear-r" aria-hidden="true" />
      <div className="nt-pill-inner" style={{ flex: 1 }}>{inner}</div>
      {skip && <span className="nt-skip-wing"><SkipArrows direction={skip} /></span>}
    </div>
  );
}
