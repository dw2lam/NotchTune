import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import './mock.css';
import GlassSurface from '../components/GlassSurface';
import { BellIcon, GearIcon, GridIcon, PowerIcon, TerminalIcon, NoteIcon } from './icons';

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

export type IslandTab = 'agents' | 'music' | 'myspace' | 'reminders';

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
      {(
        [
          ['agents', 'Agents', <TerminalIcon key="i" />],
          ['music', 'Music', <NoteIcon key="i" />],
          ['myspace', 'Myspace', <GridIcon key="i" />],
          ['reminders', 'Reminders', <BellIcon key="i" />],
        ] as const
      ).map(([id, label, icon]) => (
        <button
          key={id} type="button" data-tab={id}
          className={`nt-tab ${tab === id ? 'is-on' : ''}`}
          onClick={() => onTab?.(id)}
        >
          {icon} {label}
        </button>
      ))}
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
  usage, tab, onTab, ambientArt, glass = 'clear', tintStrength = 0.22, showNotchGap = true, children, className = '',
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
      width="min(620px, 100%)"
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

/* Guided-tour coach bubble (TourCoachView): ink 0.94 capsule-ish r13,
   stroke white 0.12, icon tint by phase, 11.5 medium paper text. */
export function TourCoach({ icon, tint, text }: { icon: 'cursor' | 'check' | 'sparkles'; tint: string; text: string }) {
  return (
    <div className="nt nt-coach">
      <svg viewBox="0 0 24 24" style={{ fill: tint }}>
        {icon === 'cursor' && <path d="M4 2l16 7.5-6.8 1.9L15 18l-2.6 1.2-1.9-6.6L4 16V2z" />}
        {icon === 'check' && <path d="M12 2a10 10 0 100 20 10 10 0 000-20zm-1.2 14.5L6.5 12.2l1.4-1.4 2.9 2.9 5.3-5.3 1.4 1.4-6.7 6.7z" />}
        {icon === 'sparkles' && <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8L12 2zm7 11l.9 2.6L22 16.5l-2.1.9L19 20l-.9-2.6-2.1-.9 2.1-.9L19 13z" />}
      </svg>
      <span>{text}</span>
      <button type="button" className="nt-coach-skip">Skip tour</button>
    </div>
  );
}
