import type { CSSProperties, ReactNode } from 'react';
import { PixelArt, PixelPair } from '../components/PixelArt';
import { Shot } from '../components/Shot';
import { Section } from '../components/Section';

type Tint = 'graphite' | 'grass' | 'violet' | 'sky' | 'rose' | 'ember';

/* A still of the 2.1.5 Settings window (SettingsView / AppearanceSettingsPane):
   frosted glass over the desktop, System Settings-style tiles, Personalization's
   preview card with both displays linked by Sync. */
const SIDEBAR: { label: string; tint: Tint; glyph?: ReactNode; on?: boolean; gapAfter?: boolean }[] = [
  { label: 'General', tint: 'graphite', glyph: <G d="M8 5.6a2.4 2.4 0 1 0 0 4.8 2.4 2.4 0 0 0 0-4.8Zm5.6 3.3-1.3-.3a4.4 4.4 0 0 1-.4 1l.7 1.1-1.3 1.3-1.1-.7a4.4 4.4 0 0 1-1 .4l-.3 1.3H7.1l-.3-1.3a4.4 4.4 0 0 1-1-.4l-1.1.7-1.3-1.3.7-1.1a4.4 4.4 0 0 1-.4-1L2.4 8.9V7.1l1.3-.3a4.4 4.4 0 0 1 .4-1l-.7-1.1 1.3-1.3 1.1.7a4.4 4.4 0 0 1 1-.4l.3-1.3h1.8l.3 1.3a4.4 4.4 0 0 1 1 .4l1.1-.7 1.3 1.3-.7 1.1c.2.3.3.6.4 1l1.3.3Z" />, gapAfter: true },
  { label: 'Setup', tint: 'grass', glyph: <G d="M2.3 3h11.4c.4 0 .8.4.8.8v8.4c0 .4-.4.8-.8.8H2.3a.8.8 0 0 1-.8-.8V3.8c0-.4.4-.8.8-.8Zm1.6 3.1L5.7 8 3.9 9.9l.8.7L7.2 8 4.7 5.4Zm3.4 3.7v1.1h4V9.8Z" /> },
  { label: 'Personalization', tint: 'violet', on: true },
  { label: 'Display', tint: 'sky', glyph: <G d="M2.6 2.8h10.8c.4 0 .7.3.7.7v6.8c0 .4-.3.7-.7.7H2.6a.7.7 0 0 1-.7-.7V3.5c0-.4.3-.7.7-.7Zm3.9 9h3l.4 1.6H6.1Z" />, gapAfter: true },
  { label: 'Sound', tint: 'rose', glyph: <G d="M2.5 6h2.6L8.8 3v10L5.1 10H2.5Zm8.3.1a2.6 2.6 0 0 1 0 3.8l-.8-.8a1.5 1.5 0 0 0 0-2.2Zm1.7-1.7a5 5 0 0 1 0 7.2l-.8-.8a3.8 3.8 0 0 0 0-5.6Z" /> },
  { label: 'Music', tint: 'ember', glyph: <G d="M11.5 2v8.2A2 2 0 1 1 10 8.3V4.6l-4 1v5.6A2 2 0 1 1 4.5 9.3V3.6Z" /> },
];

function G({ d }: { d: string }) {
  return <svg viewBox="0 0 16 16"><path fillRule="evenodd" d={d} /></svg>;
}
function LaptopIcon() {
  return <svg className="ss-ico" viewBox="0 0 16 16"><path d="M3.5 4h9v6h-9ZM1.5 11.5h13" /></svg>;
}
function DisplayIcon() {
  return <svg className="ss-ico" viewBox="0 0 16 16"><path d="M2.5 3h11v7.5h-11ZM6 13h4M8 10.5V13" /></svg>;
}
function LinkIcon() {
  return <svg className="ss-ico ss-link" viewBox="0 0 16 16"><path d="M6.6 9.4 9.4 6.6M5.4 7.8 4 9.2a2 2 0 0 0 2.8 2.8l1.4-1.4M10.6 8.2 12 6.8A2 2 0 0 0 9.2 4L7.8 5.4" /></svg>;
}

function Wall({ kind }: { kind: 'notch' | 'ext' }) {
  return (
    <span className={`ss-wall ${kind}`}>
      {kind === 'ext' && <span className="ss-menubar">NotchTune <em>File</em></span>}
      <span className="ss-wall-pill"><PixelArt char="claude" /></span>
      <span className="ss-wall-label">
        {kind === 'notch' ? <LaptopIcon /> : <DisplayIcon />}
        {kind === 'notch' ? 'MacBook notch' : 'External display'}
      </span>
    </span>
  );
}

function SettingsShot() {
  return (
    <div className="ss">
      <div className="ss-side">
        <span className="ss-lights"><i /><i /><i /></span>
        {SIDEBAR.map((row) => (
          <span key={row.label}>
            <span className={`ss-row${row.on ? ' on' : ''}`}>
              <span className={`ss-tile tint-${row.tint}`}>{row.glyph ?? <PixelArt char="claude" />}</span>
              {row.label}
            </span>
            {row.gapAfter && <span className="ss-gap" />}
          </span>
        ))}
      </div>
      <div className="ss-main">
        <div className="ss-hero">
          <span className="ss-hero-tile tint-violet"><PixelArt char="claude" /></span>
          <div>
            <div className="ss-hero-title">Personalization</div>
            <div className="ss-hero-sub">Make the notch yours. Every change shows up live in the preview.</div>
          </div>
        </div>
        <div className="ss-card">
          <div className="ss-walls"><Wall kind="notch" /><Wall kind="ext" /></div>
          <div className="ss-zone-row">
            <span className="ss-zones">
              <span><LaptopIcon /> MacBook notch</span>
              <LinkIcon />
              <span><DisplayIcon /> External display</span>
            </span>
            <span className="ss-sync"><i /> SYNC</span>
          </div>
          <span className="ss-seg"><span className="on">Auto</span><span>Idle</span><span>Working</span><span>Waiting</span></span>
        </div>
        <p className="ss-note">Sync is on: every choice applies to the MacBook notch and the external display.</p>
      </div>
    </div>
  );
}

/* The app's twenty characters, in its picker order. */
const CHARACTERS: [string, string][] = [
  ['dino', 'Dino'], ['ghost', 'Ghost'], ['crab', 'Crab'], ['duck', 'Duck'], ['claude', 'Claude'],
  ['cat', 'Cat'], ['robot', 'Robot'], ['octopus', 'Octopus'], ['frog', 'Frog'], ['slime', 'Slime'],
  ['blob', 'Blob'], ['poo', 'Poo'], ['johnPork', 'John Pork'], ['tungTung', 'Tung Tung'], ['tralalero', 'Tralalero'],
  ['bombardiro', 'Bombardiro'], ['ballerina', 'Ballerina'], ['chimpanzini', 'Chimpanzini'], ['lirili', 'Lirilì'], ['patapim', 'Patapim'],
];

/* The character picker, with the three ways a character can move. */
function Picker() {
  return (
    <div className="picker">
      <div className="picker-head"><b>Character</b><span>20</span></div>
      <div className="picker-grid">
        {CHARACTERS.map(([id], i) => (
          <span className={`picker-tile${id === 'claude' ? ' on' : ''}`} style={{ '--i': i } as CSSProperties} key={id}>
            <PixelPair char={id} />
          </span>
        ))}
      </div>
      <div className="picker-foot">
        <span>Motion</span>
        <span className="ss-seg"><span className="on">Calm</span><span>Lively</span><span>Still</span></span>
      </div>
    </div>
  );
}

export default function Personalization() {
  return (
    <Section
      id="personalize" index="06" label="Personalization" wide
      title="Make it yours."
      line="Twenty characters, frosted Settings, and Sync to style the MacBook notch and an external display at once."
    >
      <div className="slab slab-ss reveal">
        <Shot className="ss-shot" label="The NotchTune Settings window on Personalization: previews of the MacBook notch and an external display side by side, linked, with SYNC lit.">
          <SettingsShot />
        </Shot>
        <Shot className="card picker-card" label={`The character picker with all twenty characters: ${CHARACTERS.map(([, n]) => n).join(', ')}. Claude is selected, and Motion is set to Calm, with Lively and Still.`}>
          <Picker />
        </Shot>
      </div>
    </Section>
  );
}
