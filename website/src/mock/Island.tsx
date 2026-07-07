import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import './mock.css';
import GlassSurface from '../components/GlassSurface';
import { GearIcon, PowerIcon, TerminalIcon, NoteIcon } from './icons';

/* ============================================================
   1:1 opened-island shell (IslandPanelView.swift).
   Panel: 520pt wide, r 0 0 22 22, stroke white@0.07.
   Glass renders through the React Bits <GlassSurface />
   (SVG displacement refraction) with the app's ink tint
   overlay at strength 0.22 (LiquidGlass.swift:89-112);
   'off' falls back to solid V6Palette.ink.
   ============================================================ */

export type UsageTone = 'ok' | 'warn' | 'hot';

export function UsageChip({ name, window: win, pct, tone = 'ok' }: {
  name: string; window: string; pct: number; tone?: UsageTone;
}) {
  return (
    <span className="nt-uchip">
      <b>{name}</b>
      <em>{win}</em>
      <i className={`nt-u-${tone}`}>{pct}%</i>
    </span>
  );
}

export type IslandTab = 'agents' | 'music';

export function TabBar({ tab, onTab }: { tab: IslandTab; onTab?: (t: IslandTab) => void }) {
  const barRef = useRef<HTMLDivElement>(null);
  const [ind, setInd] = useState<{ left: number; top: number; width: number; height: number } | null>(null);

  useLayoutEffect(() => {
    const bar = barRef.current;
    if (!bar) return;
    const measure = () => {
      const btn = bar.querySelector<HTMLElement>(`[data-tab="${tab}"]`);
      if (btn) setInd({ left: btn.offsetLeft, top: btn.offsetTop, width: btn.offsetWidth, height: btn.offsetHeight });
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(bar);
    return () => ro.disconnect();
  }, [tab]);

  return (
    <div className="nt-tabbar" ref={barRef}>
      {ind && <span className="nt-tab-ind" style={ind} />}
      <button
        type="button" data-tab="agents"
        className={`nt-tab ${tab === 'agents' ? 'is-on' : ''}`}
        onClick={() => onTab?.('agents')}
      >
        <TerminalIcon /> Agents
      </button>
      <button
        type="button" data-tab="music"
        className={`nt-tab ${tab === 'music' ? 'is-on' : ''}`}
        onClick={() => onTab?.('music')}
      >
        <NoteIcon /> Music
      </button>
    </div>
  );
}

/* panel-height morph: the real island animates its height when tab
   content changes (OverlayPanelController measures + springs) */
function AnimatedHeight({ children }: { children: ReactNode }) {
  const innerRef = useRef<HTMLDivElement>(null);
  const [h, setH] = useState<number | null>(null);
  useLayoutEffect(() => {
    const el = innerRef.current;
    if (!el) return;
    setH(el.offsetHeight);
    const ro = new ResizeObserver(() => setH(el.offsetHeight));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return (
    <div className="nt-height" style={{ height: h ?? 'auto' }}>
      <div ref={innerRef}>{children}</div>
    </div>
  );
}

export function IslandPanel({
  usage, tab, onTab, ambientArt, glass = 'clear', tintStrength = 0.5, showNotchGap = true, children, className = '',
}: {
  usage?: ReactNode;
  tab?: IslandTab;
  onTab?: (t: IslandTab) => void;
  /** album-art ambience behind content when music plays (opacity .12 blur 20) */
  ambientArt?: string;
  glass?: 'clear' | 'frosted' | 'off';
  /** ink tint over the glass, 0–1 (LiquidGlass tintStrength; app default 0.22) */
  tintStrength?: number;
  showNotchGap?: boolean;
  children: ReactNode;
  className?: string;
}) {
  const inner = (
    <>
      {ambientArt && <div className="nt-ambient" style={{ backgroundImage: `url(${ambientArt})` }} />}
      <div className="nt-header">
        <div className="nt-usage">{usage}</div>
        {showNotchGap ? <div className="nt-header-gap" /> : <div />}
        <div className="nt-tools">
          <button type="button" className="nt-toolbtn" aria-label="Settings"><GearIcon /></button>
          <button type="button" className="nt-toolbtn" aria-label="Quit"><PowerIcon /></button>
        </div>
      </div>
      {tab !== undefined && <TabBar tab={tab} onTab={onTab} />}
      <AnimatedHeight>
        <div className="nt-tabfade" key={tab ?? 'static'}>{children}</div>
      </AnimatedHeight>
    </>
  );

  if (glass === 'off') {
    return <div className={`nt nt-island ${className}`.trim()}>{inner}</div>;
  }

  return (
    <GlassSurface
      width="min(520px, 100%)"
      height="auto"
      borderRadius={22}
      borderWidth={0.03}
      brightness={55}
      opacity={0.9}
      blur={16}
      displace={1.2}
      distortionScale={-90}
      redOffset={0}
      greenOffset={5}
      blueOffset={10}
      backgroundOpacity={0}
      saturation={1.1}
      className={`nt nt-island nt-island-gs ${glass === 'frosted' ? 'is-frosted' : ''} ${className}`.trim()}
      style={{ borderRadius: '0 0 22px 22px' }}
    >
      <div
        className="nt-gs-tint"
        style={{ background: `rgba(6, 6, 8, ${glass === 'frosted' ? Math.max(0.55, tintStrength) : tintStrength})` }}
      />
      {inner}
    </GlassSurface>
  );
}
