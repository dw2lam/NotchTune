import { ClosedPill, type PillMode } from '../mock';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { Section } from '../components/Section';

const MOMENTS: { label: string; tone: string; mode: PillMode; said: string }[] = [
  {
    label: 'Working', tone: 'work', said: 'Claude in api, running swift test, 1 minute 47 seconds in',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'working', title: 'Claude · api', subtitle: 'Running swift test', timer: '1:47' } },
  },
  {
    label: 'Needs you', tone: 'wait', said: 'Codex needs approval for git push origin main',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'approval', title: 'Codex needs approval', subtitle: 'git push origin main', timer: '0:21' } },
  },
  {
    label: 'Finished', tone: 'done', said: 'Claude finished: the build passes, after 2 minutes 40 seconds',
    mode: { kind: 'live', char: 'dino', activity: { kind: 'finished', title: 'Claude finished', subtitle: 'Build passes · 2m 40s' } },
  },
];

export default function Agents() {
  const phone = usePhone();
  return (
    <Section
      id="agents" index="02" label="In the notch"
      title="See it work without looking away."
      line="The closed notch widens with what an agent is doing, turns amber when it needs you, and checks off when it’s done."
    >
      <div className="slab slab-cascade reveal">
        {MOMENTS.map((m) => (
          <div className={`card moment m-${m.tone}`} key={m.label}>
            <div className="hang">
              <Shot label={`The closed notch, ${m.label.toLowerCase()}: ${m.said}.`}>
                <ClosedPill layout={phone ? 'pill' : 'notch'} alignNotch={false} mode={m.mode} />
              </Shot>
            </div>
            <p className="tag">{m.label}</p>
          </div>
        ))}
      </div>
    </Section>
  );
}
