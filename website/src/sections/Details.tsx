import { SecHead } from '../components/SecHead';

const FIGURES = [
  { n: '32', title: 'Original sounds', text: 'Synthesized from scratch and matched to the loudness of macOS’s own alerts, from a desk bell for “needs you” to a soft resolve when work is done.' },
  { n: '0', title: 'Accounts or trackers', text: 'No sign-in, no telemetry, no server. Everything runs on your Mac, and the code is on GitHub under the GPL.' },
  { n: '1', title: 'Click to update', text: 'New versions arrive through Sparkle and install in place, so you stay current without thinking about it.' },
];

export default function Details() {
  return (
    <section id="details" className="sec sec-ink" aria-labelledby="details-title">
      <div className="frame">
        <SecHead
          num="11" label="Details" note="Local-first" id="details-title"
          title={<>Thoughtful, all the way down.</>}
          lede="The small things are part of the calm: sounds that don’t startle, nothing that phones home, and updates that look after themselves."
        />
        <div className="stage figures reveal">
          {FIGURES.map((f) => (
            <div className="figure" key={f.title}>
              <strong aria-hidden="true">{f.n}</strong>
              <h3><span className="sr-only">{f.n} </span>{f.title}</h3>
              <p>{f.text}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
