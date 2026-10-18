import { ClosedPill, type PillMode } from '../mock';
import { Fit } from '../components/Fit';
import { Shot } from '../components/Shot';
import { Screen } from '../components/Screen';

const MOMENTS: { label: string; dot: string; mode: PillMode }[] = [
  {
    label: 'Working', dot: 'work',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'working', title: 'Claude · api', subtitle: 'Running swift test', timer: '3:12' } },
  },
  {
    label: 'Needs you', dot: 'wait',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'approval', title: 'Codex needs approval', subtitle: 'git push origin main', timer: '0:21' } },
  },
  {
    label: 'Finished', dot: 'done',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'finished', title: 'Claude finished', subtitle: 'Edited 4 files · 3m 12s' } },
  },
];

export default function Agents() {
  return (
    <section id="agents" className="section" aria-labelledby="agents-title">
      <div className="wrap">
        <header className="head">
          <p className="eyebrow reveal">Agents</p>
          <h2 id="agents-title" className="h2 reveal d1">Watch it work without opening&nbsp;anything.</h2>
          <p className="lede reveal d2">
            While Claude Code or Codex runs, the closed notch widens to show what it’s doing and for how long.
            It turns amber the moment an agent needs you, and checks off quietly when it’s done.
          </p>
        </header>
        <div className="stage glass reveal">
          <Shot label="Three closed notch pills: Claude running swift test for 3 minutes 12 seconds; Codex needing approval for git push origin main; Claude finished after 3 minutes 12 seconds, having edited 4 files.">
            <div className="moments">
              {MOMENTS.map((m) => (
                <div className="moment" key={m.label}>
                  <span className="moment-label"><i className={m.dot} />{m.label}</span>
                  <Fit width={640}>
                    <Screen slice minimal>
                      <ClosedPill layout="notch" mode={m.mode} />
                    </Screen>
                  </Fit>
                </div>
              ))}
            </div>
          </Shot>
        </div>
      </div>
    </section>
  );
}
