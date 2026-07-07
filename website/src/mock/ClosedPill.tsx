import type { ReactNode } from 'react';
import './mock.css';
import { SPRITES, SPRITES_RUN, spriteSVG } from '../lib/sprites';
import { PlayIcon, PauseIcon } from './icons';

/* ============================================================
   1:1 closed pill (V6ClosedPillShape + V6NotchContent):
   flat top, semicircular bottom (r = h/2), external sim 38pt
   tall, min-width 70, edge pad h/2, inner gap 8.
   Modes: music notification / music compact / agents / idle.
   ============================================================ */

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
              <span className="nt-pill-title">{mode.title}</span>
              <span className="nt-pill-artist">{mode.artist}</span>
            </span>
            <span className="nt-pill-gap" />
            <span style={{ width: 18, height: 18, color: mode.accent ?? 'var(--nt-paper)', display: 'grid', placeItems: 'center' }}>
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
            {mode.label && <span className="nt-pill-label">{mode.label}</span>}
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
