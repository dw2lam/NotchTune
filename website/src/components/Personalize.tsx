import { useState, type ReactNode } from 'react';
import { Sprite } from './Sprite';
import './MacSettings.css';

/* A 1:1-in-spirit mock of the app's Settings window (SettingsView.swift /
   AppearanceSettingsPane.swift, 2.1.5): a frosted dark glass window over the
   desktop, System Settings-style coloured section tiles with filled white
   glyphs, the sky accent, SF Pro type, and Personalization's preview card
   with the MacBook notch / External display switcher and its SYNC button. */

type Pane = 'general' | 'personalization';
type Tint = 'graphite' | 'grass' | 'violet' | 'sky' | 'rose' | 'ember';

const SIDEBAR: { id: string; label: string; tint: Tint; glyph: ReactNode; pane?: Pane }[] = [
  { id: 'general', label: 'General', tint: 'graphite', glyph: <GearGlyph />, pane: 'general' },
  { id: 'setup', label: 'Setup', tint: 'grass', glyph: <TerminalGlyph /> },
  { id: 'personalization', label: 'Personalization', tint: 'violet', glyph: null, pane: 'personalization' },
  { id: 'display', label: 'Display', tint: 'sky', glyph: <MonitorGlyph /> },
  { id: 'sound', label: 'Sound', tint: 'rose', glyph: <SpeakerGlyph /> },
  { id: 'music', label: 'Music', tint: 'ember', glyph: <NoteGlyph /> },
];

/* The app's twenty characters, in its picker order. */
const CHARACTERS: [string, string][] = [
  ['dino', 'Dino'], ['ghost', 'Ghost'], ['crab', 'Crab'], ['duck', 'Duck'], ['claude', 'Claude'],
  ['cat', 'Cat'], ['robot', 'Robot'], ['octopus', 'Octopus'], ['frog', 'Frog'], ['slime', 'Slime'],
  ['blob', 'Blob'], ['poo', 'Poo'], ['johnPork', 'John Pork'], ['tungTung', 'Tung Tung'], ['tralalero', 'Tralalero'],
  ['bombardiro', 'Bombardiro'], ['ballerina', 'Ballerina'], ['chimpanzini', 'Chimpanzini'], ['lirili', 'Lirilì'], ['patapim', 'Patapim'],
];

export default function Personalize() {
  const [pane, setPane] = useState<Pane>('personalization');
  const [character, setCharacter] = useState('dino');

  return (
    <section id="personalize" className="section">
      <div className="section-head reveal">
        <h2>Personalize every pixel.</h2>
        <p>
          A Settings window in frosted glass shapes exactly what the notch shows and how it behaves: live activity,
          density, the outward top curve, your pixel buddy and how much it moves, Liquid Glass. Your MacBook notch
          and an external display each get their own profile, or turn on Sync to style both at once.
        </p>
      </div>

      <div className="mset-stage reveal" style={{ backgroundImage: 'url(/assets/wallpapers/purple.jpg)' }}>
        <div className="mset" role="group" aria-label="NotchTune Settings window (mock)">
          <nav className="mset-sidebar" aria-label="Settings sections">
            <span className="mset-lights" aria-hidden="true"><i /><i /><i /></span>
            {SIDEBAR.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`mset-side-row${item.pane === pane ? ' is-on' : ''}`}
                onClick={() => item.pane && setPane(item.pane)}
                aria-current={item.pane === pane ? 'page' : undefined}
                tabIndex={item.pane ? 0 : -1}
              >
                <TintTile tint={item.tint} size="side">
                  {item.glyph ?? <Sprite char={character} className="mset-tile-sprite" />}
                </TintTile>
                {item.label}
              </button>
            ))}
          </nav>
          <div className="mset-detail">
            {pane === 'personalization'
              ? <PersonalizationPane character={character} onCharacter={setCharacter} />
              : <GeneralPane character={character} />}
          </div>
        </div>
      </div>
    </section>
  );
}

/* ---------- panes ---------- */

function PersonalizationPane({ character, onCharacter }: { character: string; onCharacter: (c: string) => void }) {
  const [zone, setZone] = useState<'notch' | 'external'>('notch');
  const [sync, setSync] = useState(true);

  const pickZone = (z: 'notch' | 'external') => {
    setZone(z);
    setSync(false);
  };

  return (
    <>
      <Hero
        tint="violet"
        art={<Sprite char={character} className="mset-hero-sprite" />}
        title="Personalization"
        subtitle="Make the notch yours. Every change shows up live in the preview."
      />

      <div className="mset-card mset-preview-card">
        <div className={`mset-previews${sync ? ' two' : ''}`}>
          {(sync || zone === 'notch') && <DisplayPreview kind="notch" character={character} />}
          {(sync || zone === 'external') && <DisplayPreview kind="external" character={character} />}
        </div>
        <div className="mset-zone-row">
          <span className={`mset-zones${sync ? ' is-synced' : ''}`} role="radiogroup" aria-label="Display profile">
            <button type="button" role="radio" aria-checked={sync || zone === 'notch'} className={!sync && zone === 'notch' ? 'is-on' : ''} onClick={() => pickZone('notch')}>
              <LaptopIcon /> MacBook notch
            </button>
            {sync && <LinkIcon />}
            <button type="button" role="radio" aria-checked={sync || zone === 'external'} className={!sync && zone === 'external' ? 'is-on' : ''} onClick={() => pickZone('external')}>
              <DisplayIcon /> External display
            </button>
          </span>
          <button type="button" className={`mset-sync${sync ? ' is-on' : ''}`} aria-pressed={sync} onClick={() => setSync(!sync)}>
            <i aria-hidden="true" /> SYNC
          </button>
        </div>
        <Segmented options={['Auto', 'Idle', 'Working', 'Waiting']} />
      </div>
      <p className="mset-note">
        {sync
          ? 'Sync is on: every choice applies to the MacBook notch and the external display. Pick one display to set it on its own.'
          : 'Choose which screen type you are configuring. NotchTune applies the matching profile automatically when the overlay moves.'}
      </p>

      <Section title="Character">
        <div className="mset-row-text mset-tiles-head">
          <span>Pixel character</span>
          <small>Shown in the closed island.</small>
        </div>
        <div className="mset-tiles chars">
          {CHARACTERS.map(([id, name]) => (
            <Tile key={id} selected={character === id} onClick={() => onCharacter(id)} caption={name}>
              <span className="mset-char"><Sprite char={id} className="mset-sprite" /></span>
            </Tile>
          ))}
        </div>
        <Row label="Character motion" detail="Calm keeps it gentle in the corner of your eye. Lively adds hops and walk cycles; Still holds one pose per state.">
          <Segmented options={['Calm', 'Lively', 'Still']} />
        </Row>
        <Row label="Color by agent" detail="Tint the character with the agent it's showing: Codex blue, Claude orange, Gemini green.">
          <Switch />
        </Row>
      </Section>

      <Section title="Notch">
        <Row label="Density"><Segmented options={['Regular', 'Compact']} /></Row>
        <Row label="Notch top curve" detail="Flare the notch outward where it meets the top of the screen.">
          <Switch on />
        </Row>
        <Row label="Live activity" detail="Let the notch widen to show what an agent is doing, when it needs you, and when it finishes.">
          <Segmented options={['Off', 'Events only', 'While active']} initial={2} />
        </Row>
      </Section>

      <Section title="Liquid Glass">
        <Row label="Use Liquid Glass"><Switch on /></Row>
        <Row label="Material"><Segmented options={['Clear', 'Frosted']} /></Row>
      </Section>
    </>
  );
}

function GeneralPane({ character }: { character: string }) {
  const { greeting, tint } = timeOfDay(new Date().getHours());
  return (
    <>
      <div className={`mset-welcome tint-${tint}`}>
        <span className="mset-stage-notch"><Sprite char={character} className="mset-welcome-sprite" /></span>
        <div className="mset-welcome-text">
          <strong>{greeting}</strong>
          <span><i className="mset-dot" aria-hidden="true" /> An agent is working</span>
        </div>
      </div>
      <Section title="Startup">
        <Row label="Launch at Login"><Switch on /></Row>
        <Row label="Monitor"><Popup value="Automatic" /></Row>
      </Section>
      <Section title="Behavior">
        <Row label="Hide icon in Dock"><Switch on /></Row>
        <Row label="Haptic feedback on hover"><Switch /></Row>
        <Row label="Reply from completion card"><Switch on /></Row>
        <Row label="Open on hover" detail="Rest the pointer on the notch this long to open it. Clicking always opens it.">
          <Segmented options={['Off', 'Quick', 'Normal', 'Relaxed']} initial={2} />
        </Row>
      </Section>
    </>
  );
}

/* The welcome card's greeting and colour follow the hour, like the app's. */
function timeOfDay(hour: number): { greeting: string; tint: Tint | 'indigo' } {
  if (hour >= 5 && hour < 12) return { greeting: 'Good morning', tint: 'ember' };
  if (hour >= 12 && hour < 17) return { greeting: 'Good afternoon', tint: 'sky' };
  if (hour >= 17 && hour < 22) return { greeting: 'Good evening', tint: 'violet' };
  return { greeting: 'Working late?', tint: 'indigo' };
}

/* ---------- pieces ---------- */

function Hero({ tint, art, title, subtitle }: { tint: Tint; art: ReactNode; title: string; subtitle: string }) {
  return (
    <div className="mset-hero">
      <TintTile tint={tint} size="hero">{art}</TintTile>
      <div>
        <div className="mset-hero-title">{title}</div>
        <div className="mset-hero-sub">{subtitle}</div>
      </div>
    </div>
  );
}

function TintTile({ tint, size, children }: { tint: Tint; size: 'side' | 'hero'; children: ReactNode }) {
  return <span className={`mset-icon is-${size} tint-${tint}`}>{children}</span>;
}

function DisplayPreview({ kind, character }: { kind: 'notch' | 'external'; character: string }) {
  return (
    <span className={`mset-wall ${kind}`}>
      {kind === 'external' && (
        <span className="mset-menubar" aria-hidden="true"><b></b> NotchTune <em>File</em></span>
      )}
      <span className="mset-pill">
        <Sprite char={character} className="mset-pill-sprite" />
      </span>
      <span className="mset-wall-label">{kind === 'notch' ? <LaptopIcon /> : <DisplayIcon />} {kind === 'notch' ? 'MacBook notch' : 'External display'}</span>
    </span>
  );
}

function Section({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <div className="mset-section">
      {title && <div className="mset-section-title">{title}</div>}
      <div className="mset-card">{children}</div>
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

function Tile({ selected, onClick, caption, children }: {
  selected: boolean; onClick: () => void; caption: string; children: ReactNode;
}) {
  return (
    <button type="button" className={`mset-tile${selected ? ' is-on' : ''}`} onClick={onClick} aria-pressed={selected}>
      <span className="mset-tile-art">{children}</span>
      <span className="mset-tile-cap">{caption}</span>
    </button>
  );
}

/* ---------- glyphs (white, filled, SF-Symbol-like) ---------- */

function Glyph({ d }: { d: string }) {
  return <svg viewBox="0 0 16 16" aria-hidden="true"><path fillRule="evenodd" d={d} /></svg>;
}
function GearGlyph() { return <Glyph d="M8 5.6a2.4 2.4 0 1 0 0 4.8 2.4 2.4 0 0 0 0-4.8Zm5.6 3.3-1.3-.3a4.4 4.4 0 0 1-.4 1l.7 1.1-1.3 1.3-1.1-.7a4.4 4.4 0 0 1-1 .4l-.3 1.3H7.1l-.3-1.3a4.4 4.4 0 0 1-1-.4l-1.1.7-1.3-1.3.7-1.1a4.4 4.4 0 0 1-.4-1L2.4 8.9V7.1l1.3-.3a4.4 4.4 0 0 1 .4-1l-.7-1.1 1.3-1.3 1.1.7a4.4 4.4 0 0 1 1-.4l.3-1.3h1.8l.3 1.3a4.4 4.4 0 0 1 1 .4l1.1-.7 1.3 1.3-.7 1.1c.2.3.3.6.4 1l1.3.3Z" />; }
function TerminalGlyph() { return <Glyph d="M2.3 3h11.4c.4 0 .8.4.8.8v8.4c0 .4-.4.8-.8.8H2.3a.8.8 0 0 1-.8-.8V3.8c0-.4.4-.8.8-.8Zm1.6 3.1L5.7 8 3.9 9.9l.8.7L7.2 8 4.7 5.4Zm3.4 3.7v1.1h4V9.8Z" />; }
function MonitorGlyph() { return <Glyph d="M2.6 2.8h10.8c.4 0 .7.3.7.7v6.8c0 .4-.3.7-.7.7H2.6a.7.7 0 0 1-.7-.7V3.5c0-.4.3-.7.7-.7Zm3.9 9h3l.4 1.6H6.1Z" />; }
function SpeakerGlyph() { return <Glyph d="M2.5 6h2.6L8.8 3v10L5.1 10H2.5Zm8.3.1a2.6 2.6 0 0 1 0 3.8l-.8-.8a1.5 1.5 0 0 0 0-2.2Zm1.7-1.7a5 5 0 0 1 0 7.2l-.8-.8a3.8 3.8 0 0 0 0-5.6Z" />; }
function NoteGlyph() { return <Glyph d="M11.5 2v8.2A2 2 0 1 1 10 8.3V4.6l-4 1v5.6A2 2 0 1 1 4.5 9.3V3.6Z" />; }

function LaptopIcon() {
  return <svg className="mset-ico" viewBox="0 0 16 16" aria-hidden="true"><path d="M3.5 4h9v6h-9ZM1.5 11.5h13" /></svg>;
}
function DisplayIcon() {
  return <svg className="mset-ico" viewBox="0 0 16 16" aria-hidden="true"><path d="M2.5 3h11v7.5h-11ZM6 13h4M8 10.5V13" /></svg>;
}
function LinkIcon() {
  return <svg className="mset-ico mset-link" viewBox="0 0 16 16" aria-hidden="true"><path d="M6.6 9.4 9.4 6.6M5.4 7.8 4 9.2a2 2 0 0 0 2.8 2.8l1.4-1.4M10.6 8.2 12 6.8A2 2 0 0 0 9.2 4L7.8 5.4" /></svg>;
}
