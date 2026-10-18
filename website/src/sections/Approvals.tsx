import { IslandPanel, NotificationSessionHeader, ApprovalCard, ShowAll, UsageCycler } from '../mock';
import { USAGE_PROVIDERS } from '../lib/demoData';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { SecHead } from '../components/SecHead';

const KEYS: [string, string][] = [
  ['⌘Y', 'Allow'],
  ['⌘N', 'Deny'],
  ['⇧⌘Y', 'Always allow'],
  ['⌘1–9', 'Pick an answer'],
  ['⏎', 'Jump back'],
];

export default function Approvals() {
  const phone = usePhone();
  return (
    <section id="approvals" className="sec sec-ink" aria-labelledby="approvals-title">
      <div className="frame">
        <SecHead
          num="03" label="Approvals" note="Keyboard first" id="approvals-title" flip
          title={<>Say yes without leaving the keyboard.</>}
          lede="Permission requests and questions open right under the notch. Answer from the keyboard, then jump straight back to the terminal that asked."
        />
        <div className="stage edge reveal">
          <div className="hang at-start">
            <Shot label="An approval card under the notch: Claude asks to run git push origin main in ~/dev/web, with Deny, Allow and Always allow Bash.">
              <div className="zoom-shot">
                <IslandPanel usage={<UsageCycler providers={USAGE_PROVIDERS} />} glass="off" divider showNotchGap={!phone}>
                  <NotificationSessionHeader title="web · Ship the landing page" prompt="ship the landing page" agent="claude" terminal="WezTerm" age="12s" />
                  <ApprovalCard command="git push origin main" path="~/dev/web" alwaysTool={phone ? undefined : 'Bash'} />
                  <ShowAll count={9} />
                </IslandPanel>
              </div>
            </Shot>
          </div>
        </div>
        <ul className="keys reveal" aria-label="Keyboard shortcuts">
          {KEYS.map(([k, label]) => (
            <li className="key" key={k}><kbd>{k}</kbd><span>{label}</span></li>
          ))}
        </ul>
      </div>
    </section>
  );
}
