import { useEffect, useRef, useState } from 'react';
import { Shuffle, Rewind, FastForward, Play, Pause, Repeat } from 'lucide-react';

/* ============================================================
   1:1 open Music tab (MusicPanelView.swift):
   HStack(20): [166×166 art r12] | VStack(16): title/artist,
   controls [16.5|22|28.6|22|16.5] gap 20, 7pt slider + times.
   Art flips ±90° over 0.18s halves on track change.
   ============================================================ */

export interface MockTrack {
  title: string;
  artist: string;
  art: string;       /* css background value or url */
  duration: number;  /* seconds */
}

export function AlbumArt({ art, size }: { art: string; size?: number }) {
  const [shown, setShown] = useState(art);
  const [phase, setPhase] = useState<'idle' | 'out' | 'in'>('idle');
  const pending = useRef(art);

  useEffect(() => {
    if (art === pending.current) return;
    pending.current = art;
    setPhase('out'); /* easeIn to 90° (0.18s) */
    const swap = setTimeout(() => {
      setShown(pending.current);
      setPhase('in'); /* swap edge-on, easeOut back to 0° */
      const settle = setTimeout(() => setPhase('idle'), 190);
      return () => clearTimeout(settle);
    }, 180);
    return () => clearTimeout(swap);
  }, [art]);

  const cls = phase === 'out' ? 'is-flipping-out' : phase === 'in' ? 'is-flipping-in' : '';
  const style = size ? { width: size, height: size, flexBasis: size } : undefined;
  return (
    <div className={`nt-art ${cls}`.trim()} style={style}>
      <div className="nt-art-inner" style={{ background: shown, backgroundSize: 'cover', backgroundPosition: 'center' }} />
    </div>
  );
}

const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

export function MusicTab({
  track, playing, position, shuffle = false, repeat = false,
  onPlayPause, onPrev, onNext, onShuffle, onRepeat, onSeek,
}: {
  track: MockTrack;
  playing: boolean;
  position: number;
  shuffle?: boolean;
  repeat?: boolean;
  onPlayPause?: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  onShuffle?: () => void;
  onRepeat?: () => void;
  onSeek?: (pos: number) => void;
}) {
  const railRef = useRef<HTMLDivElement>(null);
  const pct = Math.min(100, (position / track.duration) * 100);

  const seek = (e: React.MouseEvent) => {
    const rail = railRef.current;
    if (!rail || !onSeek) return;
    const r = rail.getBoundingClientRect();
    onSeek(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * track.duration);
  };

  return (
    <div className="nt-music">
      <AlbumArt art={track.art} />
      <div className="nt-music-col">
        <div className="nt-track-meta">
          <div className="nt-track-title">{track.title}</div>
          <div className="nt-track-artist">{track.artist}</div>
        </div>
        {/* SF-symbol glyphs: shuffle · backward.fill · play/pause.fill ·
            forward.fill · repeat (MusicPlaybackButtonsView) */}
        <div className="nt-controls">
          <button type="button" className={`nt-cbtn nt-cbtn-sm ${shuffle ? '' : 'is-off'}`} onClick={onShuffle} aria-label="Shuffle"><Shuffle strokeWidth={2.4} /></button>
          <button type="button" className="nt-cbtn nt-cbtn-md" onClick={onPrev} aria-label="Previous"><Rewind fill="currentColor" strokeWidth={0} /></button>
          <button type="button" className="nt-cbtn nt-cbtn-lg" onClick={onPlayPause} aria-label={playing ? 'Pause' : 'Play'}>
            {playing ? <Pause fill="currentColor" strokeWidth={0} /> : <Play fill="currentColor" strokeWidth={0} />}
          </button>
          <button type="button" className="nt-cbtn nt-cbtn-md" onClick={onNext} aria-label="Next"><FastForward fill="currentColor" strokeWidth={0} /></button>
          <button type="button" className={`nt-cbtn nt-cbtn-sm ${repeat ? '' : 'is-off'}`} onClick={onRepeat} aria-label="Repeat"><Repeat strokeWidth={2.4} /></button>
        </div>
        <div className="nt-progress">
          <div className="nt-rail" ref={railRef} onClick={seek}>
            <div className="nt-fill" style={{ width: `${pct}%` }} />
          </div>
          <div className="nt-times">
            <span>{fmt(position)}</span>
            <span>{fmt(track.duration)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
