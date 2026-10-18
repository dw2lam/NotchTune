import { AudioLines, ShieldCheck, RefreshCw } from 'lucide-react';

const DETAILS = [
  {
    icon: <AudioLines aria-hidden="true" size={22} strokeWidth={1.8} />,
    title: '32 original sounds',
    text: 'Synthesized from scratch and matched to the loudness of macOS’s own alerts, from a desk bell for “needs you” to a soft resolve when work is done.',
  },
  {
    icon: <ShieldCheck aria-hidden="true" size={22} strokeWidth={1.8} />,
    title: 'Local-first, open source',
    text: 'No account, no telemetry, no server. Everything runs on your Mac, and the code is on GitHub under the GPL.',
  },
  {
    icon: <RefreshCw aria-hidden="true" size={22} strokeWidth={1.8} />,
    title: 'Keeps itself current',
    text: 'New versions arrive through Sparkle and install in place, so you’re always on the latest without thinking about it.',
  },
];

export default function Details() {
  return (
    <section id="details" className="section" aria-labelledby="details-title">
      <div className="wrap">
        <header className="head">
          <h2 id="details-title" className="h2 reveal">Thoughtful, all the way&nbsp;down.</h2>
        </header>
        <div className="details">
          {DETAILS.map((d, i) => (
            <article className={`detail glass reveal${i ? ` d${i}` : ''}`} key={d.title}>
              <div className="detail-icon">{d.icon}</div>
              <h3>{d.title}</h3>
              <p>{d.text}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
