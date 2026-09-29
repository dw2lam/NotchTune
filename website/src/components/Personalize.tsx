import { useState, type ReactNode } from 'react';
import { Sprite } from './Sprite';
import './MacSettings.css';

/* A 1:1-in-spirit mock of the app's Settings window (SettingsView.swift /
   AppearanceSettingsPane.swift after the System Settings redesign): colored
   rounded-square sidebar icons, grouped Form sections, native-looking
   switches, segmented controls, pop-up menus and picture tiles. */

type Pane = 'general' | 'personalization';

const SIDEBAR: { id: string; label: string; color: string; glyph: ReactNode; pane?: Pane; gapBefore?: boolean }[] = [
  { id: 'general', label: 'General', color: '#8e8e93', glyph: <GearGlyph />, pane: 'general' },
  { id: 'setup', label: 'Setup', color: '#ff9f0a', glyph: <PuzzleGlyph /> },
  { id: 'display', label: 'Display', color: '#0a84ff', glyph: <MonitorGlyph /> },
  { id: 'sound', label: 'Sound', color: '#ff453a', glyph: <SpeakerGlyph /> },
  { id: 'music', label: 'Music', color: '#ff375f', glyph: <NoteGlyph /> },
  { id: 'personalization', label: 'Personalization', color: '#bf5af2', glyph: <PaletteGlyph />, pane: 'personalization' },
  { id: 'updates', label: 'Updates', color: '#8e8e93', glyph: <RefreshGlyph />, gapBefore: true },
  { id: 'about', label: 'About', color: '#0a84ff', glyph: <InfoGlyph /> },
];

export default function Personalize() {
  const [pane, setPane] = useState<Pane>('personalization');

  return (
    <section id="personalize" className="section">
      <div className="section-head reveal">
        <h2>Personalize every pixel.</h2>
        <p>
          A native macOS Settings window shapes exactly what the notch shows and how it behaves — live activity,
          density, the outward top curve, your pixel buddy and its colors, Liquid Glass — with a separate
          profile for your MacBook notch and any external display.
        </p>
      </div>

      <div className="mset reveal" role="group" aria-label="NotchTune Settings window (mock)">
        <div className="mset-titlebar">
          <span className="mset-lights" aria-hidden="true"><i /><i /><i /></span>
          <span className="mset-title">{pane === 'general' ? 'General' : 'Personalization'}</span>
        </div>
        <div className="mset-body">
          <nav className="mset-sidebar" aria-label="Settings sections">
            {SIDEBAR.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`mset-side-row${item.pane === pane ? ' is-on' : ''}${item.gapBefore ? ' gap' : ''}`}
                onClick={() => item.pane && setPane(item.pane)}
                aria-current={item.pane === pane ? 'page' : undefined}
                tabIndex={item.pane ? 0 : -1}
              >
                <span className="mset-icon" style={{ background: item.color }}>{item.glyph}</span>
                {item.label}
              </button>
            ))}
          </nav>
          <div className="mset-detail">
            {pane === 'personalization' ? <PersonalizationPane /> : <GeneralPane />}
          </div>
        </div>
      </div>
    </section>
  );
}

/* ---------- panes ---------- */

function PersonalizationPane() {
  const [profile, setProfile] = useState<'notch' | 'external'>('notch');
  const [character, setCharacter] = useState('dino');
  return (
    <>
      <Section title="Display Profile" footer="Choose which screen type you are configuring. NotchTune applies the matching profile automatically when the overlay moves.">
        <div className="mset-tiles two">
          <Tile selected={profile === 'external'} onClick={() => setProfile('external')} caption="External display" sub="Top-bar fallback without notch corners">
            <span className="mset-wall"><span className="mset-pill floating" /></span>
          </Tile>
          <Tile selected={profile === 'notch'} onClick={() => setProfile('notch')} caption="MacBook notch" sub="Notch-aware geometry">
            <span className="mset-wall"><span className="mset-pill" /></span>
          </Tile>
        </div>
      </Section>

      <Section title="Notch">
        <Row label="Density"><Segmented options={['Regular', 'Compact']} /></Row>
        <Row label="Live activity" detail="Widen the pill to show what an agent is doing.">
          <Segmented options={['Off', 'Events only', 'While active']} initial={2} />
        </Row>
        <Row label="Notch top curve" detail="Flare the notch outward where it meets the top of the screen.">
          <Switch on />
        </Row>
      </Section>

      <Section title="Character">
        <div className="mset-tiles chars">
          {['dino', 'ghost', 'crab', 'duck', 'claude'].map((c) => (
            <Tile key={c} selected={character === c} onClick={() => setCharacter(c)} caption={c[0].toUpperCase() + c.slice(1)}>
              <span className="mset-char"><Sprite char={c} className="mset-sprite" /></span>
            </Tile>
          ))}
        </div>
        <Row label="Color by agent" detail="Tint the character with the agent it's showing: Codex blue, Claude orange, Gemini green.">
          <Switch />
        </Row>
      </Section>

      <Section title="Liquid Glass">
        <Row label="Liquid Glass"><Switch on /></Row>
        <Row label="Material"><Segmented options={['Clear', 'Frosted']} /></Row>
      </Section>

      <Section title="Session List">
        <Row label="Usage"><Popup value="Compact" /></Row>
        <Row label="Grouping"><Popup value="None" /></Row>
        <Row label="Sorting"><Popup value="Attention" /></Row>
        <Row label="Done timeout"><Popup value="5 minutes" /></Row>
      </Section>
    </>
  );
}

function GeneralPane() {
  return (
    <>
      <Section>
        <Row label="Launch at Login"><Switch on /></Row>
        <Row label="Monitor"><Popup value="Automatic" /></Row>
      </Section>
      <Section title="Behavior">
        <Row label="Hide icon in Dock"><Switch on /></Row>
        <Row label="Haptic feedback on hover"><Switch /></Row>
        <Row label="Reply from completion card"><Switch on /></Row>
        <Row label="Open on hover" detail="Rest the pointer on the notch this long to open it. Clicking always opens it.">
          <Popup value="Normal" />
        </Row>
        <Row label="Smart suppression" detail="Don't open the notch when the agent's terminal tab is already in focus. Finishes still show a quiet peek in the pill.">
          <Switch on />
        </Row>
      </Section>
      <Section title="Getting Started">
        <Row label="Setup assistant" detail="Review AI setup, permissions, and your Liquid Glass style."><PushButton>Open</PushButton></Row>
        <Row label="Guided tour"><PushButton>Take Tour</PushButton></Row>
      </Section>
    </>
  );
}

/* ---------- controls ---------- */

function Section({ title, footer, children }: { title?: string; footer?: string; children: ReactNode }) {
  return (
    <div className="mset-section">
      {title && <div className="mset-section-title">{title}</div>}
      <div className="mset-group">{children}</div>
      {footer && <div className="mset-footer">{footer}</div>}
    </div>
  );
}

function Row({ label, detail, children }: { label: string; detail?: string; children: ReactNode }) {
  return (
    <div className="mset-row">
      <div className="mset-row-text">
        <span>{label}</span>
        {detail && <small>{detail}</small>}
      </div>
      <div className="mset-row-control">{children}</div>
    </div>
  );
}

function Switch({ on = false }: { on?: boolean }) {
  const [value, setValue] = useState(on);
  return (
    <button type="button" role="switch" aria-checked={value} className={`mset-switch${value ? ' is-on' : ''}`} onClick={() => setValue(!value)}>
      <span />
    </button>
  );
}

function Segmented({ options, initial = 0 }: { options: string[]; initial?: number }) {
  const [sel, setSel] = useState(initial);
  return (
    <span className="mset-seg" role="radiogroup">
      {options.map((o, i) => (
        <button key={o} type="button" role="radio" aria-checked={i === sel} className={i === sel ? 'is-on' : ''} onClick={() => setSel(i)}>{o}</button>
      ))}
    </span>
  );
}

function Popup({ value }: { value: string }) {
  return (
    <span className="mset-popup">
      {value}
      <svg viewBox="0 0 8 12" aria-hidden="true"><path d="M1.5 4.5 4 2l2.5 2.5M1.5 7.5 4 10l2.5-2.5" /></svg>
    </span>
  );
}

function PushButton({ children }: { children: ReactNode }) {
  return <button type="button" className="mset-push">{children}</button>;
}

function Tile({ selected, onClick, caption, sub, children }: {
  selected: boolean; onClick: () => void; caption: string; sub?: string; children: ReactNode;
}) {
  return (
    <button type="button" className={`mset-tile${selected ? ' is-on' : ''}`} onClick={onClick} aria-pressed={selected}>
      <span className="mset-tile-art">{children}</span>
      <span className="mset-tile-cap">{caption}</span>
      {sub && <span className="mset-tile-sub">{sub}</span>}
    </button>
  );
}

/* ---------- sidebar glyphs (white, SF-Symbol-like) ---------- */

function Glyph({ d }: { d: string }) {
  return <svg viewBox="0 0 16 16" aria-hidden="true"><path d={d} /></svg>;
}
function GearGlyph() { return <Glyph d="M8 5.3a2.7 2.7 0 1 0 0 5.4 2.7 2.7 0 0 0 0-5.4Zm5.6 3.6-1.3-.3a4.4 4.4 0 0 1-.4 1l.7 1.1-1.3 1.3-1.1-.7a4.4 4.4 0 0 1-1 .4l-.3 1.3H7.1l-.3-1.3a4.4 4.4 0 0 1-1-.4l-1.1.7-1.3-1.3.7-1.1a4.4 4.4 0 0 1-.4-1L2.4 8.9V7.1l1.3-.3a4.4 4.4 0 0 1 .4-1l-.7-1.1 1.3-1.3 1.1.7a4.4 4.4 0 0 1 1-.4l.3-1.3h1.8l.3 1.3a4.4 4.4 0 0 1 1 .4l1.1-.7 1.3 1.3-.7 1.1c.2.3.3.6.4 1l1.3.3Z" />; }
function PuzzleGlyph() { return <Glyph d="M6 2.5a1.5 1.5 0 0 1 3 0V4h3v3h-1.5a1.5 1.5 0 0 0 0 3H12v3.5H4V10h1.5a1.5 1.5 0 0 0 0-3H4V4h2Z" />; }
function MonitorGlyph() { return <Glyph d="M2.5 3h11v7.5h-11Zm4 8.5h3l.5 1.5H6Z" />; }
function SpeakerGlyph() { return <Glyph d="M3 6h2.5L9 3v10L5.5 10H3Zm8 .2a2.5 2.5 0 0 1 0 3.6l-.8-.8a1.4 1.4 0 0 0 0-2Zm1.6-1.6a4.8 4.8 0 0 1 0 6.8l-.8-.8a3.6 3.6 0 0 0 0-5.2Z" />; }
function NoteGlyph() { return <Glyph d="M11.5 2v8.2A2 2 0 1 1 10 8.3V4.6l-4 1v5.6A2 2 0 1 1 4.5 9.3V3.6Z" />; }
function PaletteGlyph() { return <Glyph d="M8 2a6 6 0 0 0 0 12c.9 0 1.2-.6 1-1.3-.3-.8.2-1.7 1.1-1.7H12a2 2 0 0 0 2-2A6 6 0 0 0 8 2ZM4.8 8.4a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm2-2.6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm3.2 0a1 1 0 1 1 0-2 1 1 0 0 1 0 2Zm1.8 2.2a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z" />; }
function RefreshGlyph() { return <Glyph d="M8 3a5 5 0 0 1 4.3 2.5V3.5h1.2v4h-4V6.3h1.8A3.8 3.8 0 1 0 11.8 9h1.2A5 5 0 1 1 8 3Z" />; }
function InfoGlyph() { return <Glyph d="M7.2 6.8h1.6V12H7.2Zm.8-3a1 1 0 1 1 0 2 1 1 0 0 1 0-2Z" />; }
