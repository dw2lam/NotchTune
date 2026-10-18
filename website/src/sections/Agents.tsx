import { ClosedPill, type PillMode } from '../mock';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { SecHead } from '../components/SecHead';

const MOMENTS: { label: string; key: string; note: string; mode: PillMode }[] = [
  {
    label: 'Working', key: 'k-work', note: 'What it’s doing, and for how long.',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'working', title: 'Claude · api', subtitle: 'Running swift test', timer: '3:12' } },
  },
  {
    label: 'Needs you', key: 'k-wait', note: 'Amber the moment it’s waiting on you.',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'approval', title: 'Codex needs approval', subtitle: 'git push origin main', timer: '0:21' } },
  },
  {
    label: 'Finished', key: 'k-done', note: 'A quiet check, then out of the way.',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'finished', title: 'Claude finished', subtitle: 'Edited 4 files · 3m 12s' } },
  },
];

export default function Agents() {
  const phone = usePhone();
  return (
    <section id="agents" className="sec sec-paper" aria-labelledby="agents-title">
      <div className="frame">
        <SecHead
          num="02" label="Agents" note="Live activity" id="agents-title"
          title={<>Watch it work without opening anything.</>}
          lede="While Claude Code or Codex runs, the closed notch widens to show what it’s doing and for how long. It turns amber the moment an agent needs you, and checks off quietly when it’s done."
        />
        <div className="stage moments">
          {MOMENTS.map((m) => (
            <div className="moment reveal" key={m.label}>
              <div className="moment-key">
                <span className="label"><i className={m.key} aria-hidden="true" />{m.label}</span>
                <p>{m.note}</p>
              </div>
              <div className="moment-shot">
                <Shot label={`The closed notch, ${m.label.toLowerCase()}: ${m.mode.kind === 'live' ? `${m.mode.activity.title}, ${m.mode.activity.subtitle ?? ''}` : ''}`}>
                  <div className="zoom-pill">
                    <ClosedPill layout={phone ? 'pill' : 'notch'} mode={m.mode} />
                  </div>
                </Shot>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
