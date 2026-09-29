import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import './mock.css';
import GlassSurface from '../components/GlassSurface';
import { BellIcon, GearIcon, GridIcon, PowerIcon, TerminalIcon, NoteIcon } from './icons';

/* ============================================================
   1:1 opened-island shell (IslandPanelView.swift).
   Surface = GrowingNotchShape: flat top flared by an outward 14pt
   top curve (openedEarRadius), bottom radius 22. Glass renders
   through the React Bits <GlassSurface /> with the app's ink tint
   (LiquidGlass tintStrength 0.22); 'off' = solid V6Palette.ink.
   Header: usage cycler (left) · notch gap · per-model weekly +
   glass gear/power discs (right). Tabs: Liquid Glass pill on the
   active tab (glassEffectID morph ≈ sliding capsule).
   ============================================================ */

export type UsageTone = 'ok' | 'warn' | 'hot';

const toneFor = (pct: number): UsageTone => (pct >= 90 ? 'hot' : pct >= 70 ? 'warn' : 'ok');

export interface UsageWindow {
  label: string;   /* "5h", "7d", "Fable" */
  pct: number;
  reset?: string;  /* compactRemaining: "4h43m", "1d5h", "12m" */
}

export interface UsageProvider {
  id: 'claude' | 'codex' | 'gemini';
  title: string;
  windows: UsageWindow[];
}

/** 15pt app icon (AgentAppIconProvider) — brand tile + white glyph */
export function ProviderIcon({ id }: { id: UsageProvider['id'] }) {
  return <span className={`nt-appicon nt-appicon-${id}`} aria-hidden="true"><i /></span>;
}

/** usageWindowText: label white@0.62 · pct tinted · reset @0.34 (mono) */
export function UsageWindowText({ w, showsReset = true }: { w: UsageWindow; showsReset?: boolean }) {
  return (
    <span className="nt-uwin">
      <span className="nt-uwin-label">{w.label}</span>
      <span className={`nt-u-${toneFor(w.pct)}`}>{w.pct}%</span>
      {showsReset && w.reset && <span className="nt-uwin-reset">{w.reset}</span>}
    </span>
  );
}

/** One provider at a time ("5h 12% | 7d 83%"); click steps to the next
    provider, with page dots when there is more than one (usageCycler). */
export function UsageCycler({ providers, initial = 0, showsResets = true }: {
  providers: UsageProvider[]; initial?: number; showsResets?: boolean;
}) {
  const [index, setIndex] = useState(initial);
  const p = providers[index % providers.length];
  if (!p) return null;
  return (
    <button
      type="button"
      className="nt-ucycler"
      onClick={() => setIndex((i) => (i + 1) % providers.length)}
      title={providers.length > 1 ? `${p.title} — click for ${providers[(index + 1) % providers.length].title}` : p.title}
    >
      <span className="nt-ucycler-line" key={p.id}>
        <ProviderIcon id={p.id} />
        {p.windows.map((w, i) => (
          <span className="nt-ucycler-win" key={w.label}>
            {i > 0 && <i className="nt-usep" />}
            <UsageWindowText w={w} showsReset={showsResets} />
          </span>
        ))}
      </span>
      {providers.length > 1 && (
        <span className="nt-udots">
          {providers.map((x, i) => <i key={x.id} className={i === index % providers.length ? 'is-on' : ''} />)}
        </span>
      )}
    </button>
  );
}

/* Legacy chip kept for any caller that still wants the old look. */
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
  usage, modelWeekly, tab, onTab, ambientArt, glass = 'clear', tintStrength = 0.22, showNotchGap = true,
  ears = true, divider = false, children, className = '',
}: {
  usage?: ReactNode;
  /** per-model weekly caps shown before the gear ("Fable 32% 1d5h") */
  modelWeekly?: UsageWindow[];
  tab?: IslandTab;
  onTab?: (t: IslandTab) => void;
  /** album-art ambience behind content when music plays (opacity .12 blur 20) */
  ambientArt?: string;
  glass?: 'clear' | 'frosted' | 'off';
  /** ink tint over the glass, 0–1 (LiquidGlass tintStrength; app default 0.22) */
  tintStrength?: number;
  showNotchGap?: boolean;
  /** outward 14pt top curve where the surface meets the screen edge */
  ears?: boolean;
  /** hairline under the header (notification surfaces) */
  divider?: boolean;
  children: ReactNode;
  className?: string;
}) {
  const tint = glass === 'frosted' ? Math.max(0.55, tintStrength) : tintStrength;
  const inner = (
    <>
      {ambientArt && <div className="nt-ambient" style={{ backgroundImage: `url(${ambientArt})` }} />}
      <div className={`nt-header ${divider ? 'has-divider' : ''}`}>
        <div className="nt-usage">{usage}</div>
        {showNotchGap ? <div className="nt-header-gap" /> : <div />}
        <div className="nt-tools">
          {modelWeekly?.map((w) => (
            <span className="nt-weekly" key={w.label} title={`${w.label} weekly limit`}><UsageWindowText w={w} /></span>
          ))}
          <button type="button" className="nt-gdisc nt-toolbtn" aria-label="Settings"><GearIcon /></button>
          <button type="button" className="nt-gdisc nt-toolbtn" aria-label="Quit"><PowerIcon /></button>
        </div>
      </div>
      {tab !== undefined && <TabBar tab={tab} onTab={onTab} />}
      <AnimatedHeight>
        <div className="nt-tabfade" key={tab ?? 'static'}>{children}</div>
      </AnimatedHeight>
    </>
  );

  const earEls = ears && (
    <>
      <span className={`nt-panel-ear nt-panel-ear-l is-${glass}`} style={{ ['--ear-tint' as string]: tint }} aria-hidden="true" />
      <span className={`nt-panel-ear nt-panel-ear-r is-${glass}`} style={{ ['--ear-tint' as string]: tint }} aria-hidden="true" />
    </>
  );

  if (glass === 'off') {
    return (
      <div className={`nt-island-shell ${className}`.trim()}>
        {earEls}
        <div className="nt nt-island">{inner}</div>
      </div>
    );
  }

  return (
    <div className={`nt-island-shell ${className}`.trim()}>
      {earEls}
      <GlassSurface
        width="100%"
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
        className={`nt nt-island nt-island-gs ${glass === 'frosted' ? 'is-frosted' : ''}`.trim()}
        style={{ borderRadius: '0 0 22px 22px' }}
      >
        <div className="nt-gs-tint" style={{ background: `rgba(6, 6, 8, ${tint})` }} />
        {inner}
      </GlassSurface>
    </div>
  );
}
