import { Shot } from '../components/Shot';
import { Crop } from '../components/Feature';

const STATES = [
  {
    name: 'Working', shot: 'pill-working',
    alt: 'The closed notch while Claude Code works in api: running swift test, 41 seconds in.',
  },
  {
    name: 'Needs you', shot: 'pill-waiting',
    alt: 'The closed notch turned amber: Codex needs approval to run git push origin main, waiting 13 seconds.',
  },
  {
    name: 'Done', shot: 'pill-finished',
    alt: 'The closed notch after Claude Code finished: edited 2 files in 48 seconds, with one more agent still working.',
  },
] as const;

export default function Agents() {
  return (
    <section id="agents" className="feature feature-states" aria-labelledby="agents-title">
      <div className="frame">
        <div className="feature-text reveal">
          <h2 id="agents-title" className="h2">Watch your agents work.</h2>
          <p className="lede">While Claude Code or Codex runs, the closed notch says what it’s doing and for how long. It turns amber when one needs you, and checks off when it’s done.</p>
        </div>
        <div className="states">
          {STATES.map((s) => (
            <div className="state reveal" key={s.name}>
              <p className="state-name">{s.name}</p>
              <div className="edge">
                <Crop><Shot name={s.shot} alt={s.alt} /></Crop>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
