import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import './mock.css';
import { SPRITES, SPRITES_RUN, spriteSVG } from '../lib/sprites';
import { PlayIcon, PauseIcon } from './icons';

/* ============================================================
   1:1 closed pill (V6ClosedPillShape + V6NotchContent):
   flat top, semicircular bottom (r = h/2), auto-sized to
   content (min-width 70, edge pad h/2, inner gap 8).
   Overflowing text uses the app's real marquee logic —
   30px/s ping-pong with 1.1s pauses at each end
   (V6NotchContent:407-436) — it never clips.
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

export function PixelSprite({ char, running = false }: { char: string; running?: boolean }) {
  const grid = (running && SPRITES_RUN[char]) || SPRITES[char];
  if (!grid) return null;
  return (
    <span
      className={`nt-sprite ${running ? 'is-running' : ''}`}
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

export type PillMode =
  | { kind: 'music-notification'; art: string; title: string; artist: string; playing: boolean; accent?: string }
  | { kind: 'music-compact'; art: string; playing: boolean; accent?: string }
  | { kind: 'agents'; char: string; running: boolean; label?: string; tiles?: { color: string; state: 'running' | 'idle' | 'waiting' }[] }
  | { kind: 'idle'; char: string };

export function ClosedPill({ mode, glass = false, width, children, className = '' }: {
  mode: PillMode;
  glass?: boolean;
  /** optional fixed width; omit to auto-size like the real pill */
  width?: number;
  children?: ReactNode;
  className?: string;
}) {
  let inner: ReactNode = children;
  if (!inner) {
    switch (mode.kind) {
      case 'music-notification':
        inner = (
          <>
            <span className="nt-pill-art" style={{ backgroundImage: `url(${mode.art})` }} />
            <span className="nt-pill-meta">
              <Marquee text={mode.title} className="nt-pill-title" />
              <Marquee text={mode.artist} className="nt-pill-artist" />
            </span>
            <span className="nt-pill-gap" />
            <span style={{ width: 18, height: 18, color: mode.accent ?? 'var(--nt-paper)', display: 'grid', placeItems: 'center', flex: 'none' }}>
              <span style={{ width: 10, height: 10, display: 'block' }}>
                {mode.playing ? <PauseIcon /> : <PlayIcon />}
              </span>
            </span>
          </>
        );
        break;
      case 'music-compact':
        inner = (
          <>
            <span className="nt-pill-art" style={{ backgroundImage: `url(${mode.art})` }} />
            <span className="nt-pill-gap" />
            <Waveform paused={!mode.playing} color={mode.accent} />
          </>
        );
        break;
      case 'agents':
        inner = (
          <>
            <PixelSprite char={mode.char} running={mode.running} />
            {mode.label && <Marquee text={mode.label} className="nt-pill-label" />}
            <span className="nt-pill-gap" />
            {mode.tiles && <AgentGrid tiles={mode.tiles} />}
          </>
        );
        break;
      case 'idle':
        inner = <PixelSprite char={mode.char} />;
        break;
    }
  }
  return (
    <div className={`nt nt-pill ${glass ? 'nt-glass' : ''} ${className}`.trim()} style={width ? { width } : undefined}>
      <div className="nt-pill-inner" style={{ flex: 1 }}>{inner}</div>
    </div>
  );
}
