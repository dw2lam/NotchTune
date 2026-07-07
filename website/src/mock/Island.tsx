import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import './mock.css';
import { GearIcon, PowerIcon, TerminalIcon, NoteIcon } from './icons';

/* ============================================================
   1:1 opened-island shell (IslandPanelView.swift).
   Panel: 520pt wide, ink/glass surface, r 0 0 22 22,
   stroke white@0.07. Header = usage lane | notch gap | tools.
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
  const [ind, setInd] = useState<{ left: number; width: number } | null>(null);

  useLayoutEffect(() => {
    const bar = barRef.current;
    if (!bar) return;
    const btn = bar.querySelector<HTMLElement>(`[data-tab="${tab}"]`);
    if (btn) setInd({ left: btn.offsetLeft, width: btn.offsetWidth });
  }, [tab]);

  return (
    <div className="nt-tabbar" ref={barRef}>
      {ind && <span className="nt-tab-ind" style={{ left: ind.left, width: ind.width }} />}
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
  const glassClass =
    glass === 'clear' ? 'nt-glass' : glass === 'frosted' ? 'nt-glass nt-glass-frosted' : '';
  return (
    <div className={`nt nt-island ${glassClass} ${className}`.trim()}>
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
    </div>
  );
}
