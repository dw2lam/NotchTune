const ROWS: { feat: string; cells: [string, string][] }[] = [
  { feat: 'Music playback & artwork', cells: [['yes', '✓'], ['yes', '✓'], ['no', '✕'], ['no', '✕']] },
  { feat: 'Swipe-to-skip on the closed notch', cells: [['yes', '✓'], ['part', 'some'], ['no', '✕'], ['no', '✕']] },
  { feat: 'Live AI agent monitoring', cells: [['yes', '✓'], ['no', '✕'], ['yes', '✓'], ['no', '✕']] },
  { feat: 'Live activity in the closed notch', cells: [['yes', '✓'], ['no', '✕'], ['part', 'partial'], ['no', '✕']] },
  { feat: 'Approvals & questions from the keyboard', cells: [['yes', '✓'], ['no', '✕'], ['part', 'partial'], ['no', '✕']] },
  { feat: 'Quiet toasts, smart suppression', cells: [['yes', '✓'], ['no', '✕'], ['no', '✕'], ['no', '✕']] },
  { feat: 'Usage limits with reset countdowns', cells: [['yes', '✓'], ['no', '✕'], ['part', 'some'], ['no', '✕']] },
  { feat: 'Liquid Glass interface', cells: [['yes', '✓'], ['no', '✕'], ['no', '✕'], ['no', '✕']] },
  { feat: 'Characters & personalization', cells: [['yes', '✓'], ['no', '✕'], ['no', '✕'], ['part', 'themes']] },
  { feat: 'Local-first · no telemetry', cells: [['yes', '✓'], ['part', 'varies'], ['part', 'varies'], ['yes', '✓']] },
  { feat: 'Open source · free', cells: [['yes', '✓'], ['no', '$$'], ['no', '$$'], ['part', 'some']] },
];

export default function Compare() {
  return (
    <section id="compare" className="section">
      <div className="section-head reveal">
        <h2>Most notch apps pick a lane. We didn't.</h2>
        <p>Music-only widgets, AI-only monitors, plain utilities with flat gray boxes — they each leave something on the table.</p>
      </div>

      <div className="compare glass reveal">
        <table>
          <thead>
            <tr>
              <th className="feat-col">Feature</th>
              <th className="us"><img src="/assets/icon.png" alt="" /> NotchTune</th>
              <th>Music-only<br /><span>notch widgets</span></th>
              <th>AI-only<br /><span>agent monitors</span></th>
              <th>Plain notch<br /><span>utilities</span></th>
            </tr>
          </thead>
          <tbody>
            {ROWS.map((r) => (
              <tr key={r.feat}>
                <td>{r.feat}</td>
                {r.cells.map((c, i) => (
                  <td key={i} className={i === 0 ? 'us' : undefined}>
                    <span className={c[0]}>{c[1]}</span>
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="compare-m reveal">
        <div className="cm-us glass">
          <div className="cm-head"><img src="/assets/icon.png" alt="" /> NotchTune does it all</div>
          <ul className="cm-list">
            <li>Music playback &amp; artwork</li>
            <li>Swipe-to-skip on the closed notch</li>
            <li>Live AI agent monitoring</li>
            <li>Live activity in the closed notch</li>
            <li>Approvals &amp; questions from the keyboard</li>
            <li>Quiet toasts, smart suppression</li>
            <li>Usage limits with reset countdowns</li>
            <li>Liquid Glass interface</li>
            <li>Characters &amp; personalization</li>
            <li>Local-first · no telemetry</li>
            <li>Open source &amp; free</li>
          </ul>
        </div>
        <div className="cm-vs">Where the others fall short</div>
        <div className="cm-others">
          <div className="cm-other"><b>Music-only widgets</b><span>No AI monitoring, no liquid glass, not customizable — and usually paid.</span></div>
          <div className="cm-other"><b>AI-only monitors</b><span>No music, no glass, limited approvals, and a pop-up for every event. Usually paid, too.</span></div>
          <div className="cm-other"><b>Plain notch utilities</b><span>No music, no AI — flat gray boxes.</span></div>
        </div>
      </div>

      <p className="compare-note reveal">Agents and music on one surface. It shows every state, interrupts you less, and it's free.</p>
    </section>
  );
}
