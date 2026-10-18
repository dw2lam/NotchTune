import { IslandPanel, NotificationSessionHeader, ApprovalCard, ShowAll, UsageCycler } from '../mock';
import { USAGE_PROVIDERS } from '../lib/demoData';
import { Fit } from '../components/Fit';
import { Shot } from '../components/Shot';
import { Screen } from '../components/Screen';

const KEYS: [string, string][] = [
  ['⌘Y', 'Allow'],
  ['⌘N', 'Deny'],
  ['⇧⌘Y', 'Always allow'],
  ['⌘1–9', 'Answer'],
  ['⏎', 'Jump back'],
];

export default function Approvals() {
  return (
    <section id="approvals" className="section" aria-labelledby="approvals-title">
      <div className="wrap">
        <header className="head">
          <p className="eyebrow reveal">Approvals</p>
          <h2 id="approvals-title" className="h2 reveal d1">Say yes without leaving the&nbsp;keyboard.</h2>
          <p className="lede reveal d2">
            Permission requests and questions open right under the notch. Answer from the keyboard,
            then jump straight back to the terminal that asked.
          </p>
        </header>
        <div className="stage glass reveal">
          <Shot label="An approval card under the notch: Claude asks to run git push origin main in ~/dev/web, with Deny, Allow and Always allow Bash buttons.">
            <Fit width={1000}>
              <Screen height={330} app="WezTerm">
                <IslandPanel usage={<UsageCycler providers={USAGE_PROVIDERS} />} glass="off" divider>
                  <NotificationSessionHeader title="web · Ship the landing page" prompt="ship the landing page" agent="claude" terminal="WezTerm" age="12s" />
                  <ApprovalCard command="git push origin main" path="~/dev/web" alwaysTool="Bash" />
                  <ShowAll count={9} />
                </IslandPanel>
              </Screen>
            </Fit>
          </Shot>
        </div>
        <ul className="keys reveal" aria-label="Keyboard shortcuts">
          {KEYS.map(([k, label]) => (
            <li className="key" key={k}><kbd>{k}</kbd>{label}</li>
          ))}
        </ul>
      </div>
    </section>
  );
}
