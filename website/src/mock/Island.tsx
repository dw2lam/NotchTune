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
    const btn = bar.querySelector<HTMLElement>(`[data-tab="${tab}"]`);
    if (btn) setInd({ left: btn.offsetLeft, top: btn.offsetTop, width: btn.offsetWidth, height: btn.offsetHeight });
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

export function IslandPanel({
  usage, tab, onTab, ambientArt, glass = 'clear', showNotchGap = true, children, className = '',
}: {
  usage?: ReactNode;
  tab?: IslandTab;
  onTab?: (t: IslandTab) => void;
  /** album-art ambience behind content when music plays (opacity .12 blur 20) */
  ambientArt?: string;
  glass?: 'clear' | 'frosted' | 'off';
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
      {children}
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
      borderWidth={0.04}
      brightness={55}
      opacity={0.9}
      blur={14}
      displace={0.7}
      distortionScale={-110}
      redOffset={0}
      greenOffset={8}
      blueOffset={16}
      backgroundOpacity={0}
      saturation={1.1}
      className={`nt nt-island nt-island-gs ${glass === 'frosted' ? 'is-frosted' : ''} ${className}`.trim()}
      style={{ borderRadius: '0 0 22px 22px' }}
    >
      <div className="nt-gs-tint" />
      {inner}
    </GlassSurface>
  );
}
