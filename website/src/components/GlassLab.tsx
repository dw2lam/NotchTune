import { useState, type CSSProperties } from 'react';
import { IslandTop, TabBar, UsageChip, MusicView } from './IslandParts';

type Material = 'clear' | 'frosted';

const MAT_NOTE: Record<Material, string> = {
  clear: 'Transparent, light-bending glass — the most “liquid” look.',
  frosted: 'Frosted, more opaque glass with stronger contrast.',
};

const SWATCHES: { tint: [number, number, number]; s: string; label: string }[] = [
  { tint: [0, 0, 0], s: '#34343a', label: 'Ink (none)' },
  { tint: [94, 139, 255], s: '#5e8bff', label: 'Blue' },
  { tint: [123, 92, 255], s: '#7b5cff', label: 'Violet' },
  { tint: [255, 92, 138], s: '#ff5c8a', label: 'Pink' },
  { tint: [52, 210, 123], s: '#34d27b', label: 'Green' },
  { tint: [255, 180, 59], s: '#ffb43b', label: 'Amber' },
];

const tintKey = (t: [number, number, number]) => t.join(',');

export default function GlassLab() {
  const [enabled, setEnabled] = useState(true);
  const [material, setMaterial] = useState<Material>('clear');
  const [tint, setTint] = useState<[number, number, number]>([0, 0, 0]);
  const [strength, setStrength] = useState(22);

  // Mirrors render() from the original app.js.
  const islandStyle: CSSProperties = (() => {
    if (!enabled) {
      return {
        background: '#050507',
        backdropFilter: 'none',
        WebkitBackdropFilter: 'none',
        borderColor: 'rgba(255,255,255,.06)',
        color: '#fff',
      };
    }
    const [r, g, b] = tint;
    const a = strength / 100;
    const frost = material === 'frosted' ? 0.17 : 0.04;
    const blur = material === 'frosted' ? 30 : 18;
    const tintStr = `rgba(${r},${g},${b},${a.toFixed(2)})`;
    const fr = `rgba(255,255,255,${frost})`;
    const lum = 0.299 * r + 0.587 * g + 0.114 * b;
    return {
      background:
        'linear-gradient(155deg,rgba(255,255,255,.16),transparent 38%),' +
        `linear-gradient(${tintStr},${tintStr}),` +
        `linear-gradient(${fr},${fr})`,
      backdropFilter: `blur(${blur}px) saturate(150%)`,
      WebkitBackdropFilter: `blur(${blur}px) saturate(150%)`,
      borderColor: 'rgba(255,255,255,.16)',
      color: a > 0.5 && lum > 150 ? '#10131c' : '#fff',
    };
  })();

  const groupCls = `lab-group${enabled ? '' : ' is-disabled'}`;

  return (
    <section id="glass-lab" className="section">
      <div className="section-head reveal">
        <h2>Tune the glass.</h2>
        <p>NotchTune's liquid glass is yours to shape. Drag the controls — the island reacts live, right here on the page.</p>
      </div>

      <div className="lab reveal">
        <div className="lab-stage">
          <div className="lab-wall">
            <span className="lab-wall-tag">live preview</span>
            <div className="island island-expanded lab-island" style={islandStyle}>
              <IslandTop><UsageChip name="Claude" time="5h" pct="41%" /></IslandTop>
              <TabBar active="music" />
              <MusicView />
            </div>
          </div>
        </div>

        <div className="lab-controls glass">
          <div className="lab-title">Settings → Appearance → Liquid Glass</div>

          <label className="lab-switch lab-enable">
            <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
            <span className="sw" /> Enable Liquid Glass
          </label>
          <p className="lab-note">Render the island with Apple's Liquid Glass material instead of solid black.</p>

          <div className={groupCls}>
            <div className="lab-label">Material</div>
            <div className="lab-chips">
              {(['clear', 'frosted'] as Material[]).map((m) => (
                <button
                  key={m}
                  type="button"
                  className={`mono-chip${material === m ? ' is-on' : ''}`}
                  onClick={() => enabled && setMaterial(m)}
                >
                  {m === 'clear' ? 'Clear' : 'Frosted'}
                </button>
              ))}
            </div>
            <p className="lab-note">{MAT_NOTE[material]}</p>
          </div>

          <div className={groupCls}>
            <div className="lab-label">Tint color</div>
            <div className="lab-swatches">
              {SWATCHES.map((sw) => (
                <button
                  key={sw.label}
                  type="button"
                  className={`swatch${tintKey(tint) === tintKey(sw.tint) ? ' is-on' : ''}`}
                  style={{ ['--s' as string]: sw.s } as CSSProperties}
                  aria-label={sw.label}
                  onClick={() => enabled && setTint(sw.tint)}
                />
              ))}
            </div>
          </div>

          <div className={groupCls}>
            <div className="lab-field-head"><span className="lab-label">Tint strength</span><b>{strength}%</b></div>
            <input
              type="range"
              min={0}
              max={100}
              value={strength}
              onChange={(e) => setStrength(+e.target.value)}
            />
          </div>
        </div>
      </div>
    </section>
  );
}
