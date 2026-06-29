import { useState } from 'react';

function ChipGroup({ chips, defaultIndex = 0 }: { chips: string[]; defaultIndex?: number }) {
  const [sel, setSel] = useState(defaultIndex);
  return (
    <div className="set-chips">
      {chips.map((c, i) => (
        <button
          key={c}
          className={`mono-chip${i === sel ? ' is-on' : ''}`}
          onClick={() => setSel(i)}
        >
          {c}
        </button>
      ))}
    </div>
  );
}

export default function Personalize() {
  return (
    <section id="personalize" className="section">
      <div className="section-head reveal">
        <h2>Personalize every pixel.</h2>
        <p>Past the glass and your island buddy, the Appearance settings shape exactly what the notch shows and how it behaves — and it keeps a separate profile for your MacBook notch and any external display.</p>
      </div>
      <div className="settings-panel glass reveal">
        <div className="sp-bar">
          <span className="sp-dot" /><span className="sp-dot" /><span className="sp-dot" />
          <span className="sp-title">Settings · Appearance</span>
        </div>
        <div className="sp-grid">
          <article className="set-card">
            <div className="set-kicker">Display profile</div>
            <p className="set-note">A separate look per screen, applied automatically as the overlay moves.</p>
            <ChipGroup chips={['MacBook notch', 'External display']} />
          </article>
          <article className="set-card set-toggle">
            <div><div className="set-kicker">Auto-hide</div><p className="set-note">Hide the island when nothing's active; hover the top of the screen to peek.</p></div>
            <label className="lab-switch"><input type="checkbox" defaultChecked /><span className="sw" /></label>
          </article>
          <article className="set-card">
            <div className="set-kicker">01 · Right slot</div>
            <p className="set-note">What shows on the right of the closed island.</p>
            <ChipGroup chips={['Count', 'Agents', 'None']} />
          </article>
          <article className="set-card">
            <div className="set-kicker">02 · Usage</div>
            <p className="set-note">Show compact agent usage in the opened island.</p>
            <ChipGroup chips={['Compact', 'Hidden']} />
          </article>
          <article className="set-card">
            <div className="set-kicker">Center label</div>
            <p className="set-note">External displays only — the notch covers this space on MacBook.</p>
            <ChipGroup chips={['Agent · action', 'Session name', 'Off']} />
          </article>
          <article className="set-card">
            <div className="set-kicker">03 · Session state</div>
            <p className="set-note">How rows show running, waiting, and completed.</p>
            <ChipGroup chips={['Animated dot', 'Bar', 'Glyph', 'Tint']} />
          </article>
          <article className="set-card">
            <div className="set-kicker">04 · Session grouping</div>
            <p className="set-note">Optional sections for the expanded session list.</p>
            <ChipGroup chips={['None', 'State', 'Agent', 'Project']} />
          </article>
          <article className="set-card">
            <div className="set-kicker">05 · Session sorting</div>
            <p className="set-note">The default order inside the expanded list.</p>
            <ChipGroup chips={['Attention', 'Last update']} />
          </article>
          <article className="set-card">
            <div className="set-kicker">06 · Done timeout</div>
            <p className="set-note">When completed sessions fade to the low-priority idle look.</p>
            <ChipGroup chips={['2 min', '5 min', '10 min', '20 min', 'Never']} defaultIndex={1} />
          </article>
        </div>
      </div>
    </section>
  );
}
