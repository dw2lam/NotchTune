import { IslandPanel, AgentsTab, ClosedPill, PixelSprite, type MockSession } from '../mock';
import { Fit } from '../components/Fit';
import { Shot } from '../components/Shot';
import { Screen } from '../components/Screen';

const SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'api · Make BridgeServer dispatch on a background queue',
    prompt: 'make BridgeServer dispatch on a background queue',
    activity: 'Running swift test --filter BridgeServerTests',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
  {
    state: 'done', title: 'research · Summarize the autoresearch paper',
    summary: 'Done. I pulled out the key differences that matter for our loop.',
    agent: 'codex', terminal: 'Ghostty', age: '3m',
  },
];

function VideoGlyph() {
  return <svg viewBox="0 0 16 16"><path d="M2 4.5h7.5c.6 0 1 .4 1 1v5c0 .6-.4 1-1 1H2c-.6 0-1-.4-1-1v-5c0-.6.4-1 1-1Zm9.5 2.3L15 5v6l-3.5-1.8Z" /></svg>;
}

/* The closed pill's meeting heads-up: title over the time, a call mark,
   the calendar's colour and the countdown on the right. */
function MeetingPill() {
  return (
    <ClosedPill layout="notch" mode={{ kind: 'live', char: 'dino', activity: { kind: 'working', title: '' } }}>
      <span className="nt-wing nt-wing-l">
        <PixelSprite char="dino" />
        <span className="mp-text"><b>Design review</b><em>21:29 – 21:59</em></span>
      </span>
      <span className="nt-pill-notchgap" />
      <span className="nt-wing nt-wing-r">
        <span className="mp-right"><VideoGlyph /><i />4 min</span>
      </span>
    </ClosedPill>
  );
}

function MeetingBanner() {
  return (
    <div className="meet">
      <span className="meet-bar" />
      <span className="meet-text">
        <b>Design review</b>
        <span>In 4 min · 21:29 – 21:59</span>
      </span>
      <span className="meet-join"><VideoGlyph /> Join</span>
      <span className="meet-x"><svg viewBox="0 0 16 16"><path d="M4.2 3.2 8 7l3.8-3.8 1 1L9 8l3.8 3.8-1 1L8 9l-3.8 3.8-1-1L7 8 3.2 4.2Z" /></svg></span>
    </div>
  );
}

export default function Meetings() {
  return (
    <section id="meetings" className="section" aria-labelledby="meetings-title">
      <div className="wrap">
        <header className="head">
          <p className="eyebrow reveal">Meetings</p>
          <h2 id="meetings-title" className="h2 reveal d1">Meetings, a few minutes&nbsp;early.</h2>
          <p className="lede reveal d2">
            Turn on the heads-up and the notch shows your next meeting with a countdown, plus a Join button for
            Zoom, Meet, Teams, Webex and FaceTime. It can keep NotchTune quiet while you’re in one.
            Your calendars never leave your Mac.
          </p>
        </header>
        <div className="stage glass reveal">
          <Shot label="A meeting heads-up: the closed notch reads Design review, 21:29 to 21:59, in 4 minutes. Opened, a banner offers Join above the agent sessions.">
            <Fit width={1000}>
              <div className="moments">
                <Screen slice minimal app="Calendar"><MeetingPill /></Screen>
                <Screen height={356} app="Calendar">
                  <IslandPanel tab="agents" glass="off">
                    <MeetingBanner />
                    <AgentsTab sessions={SESSIONS} total={9} />
                  </IslandPanel>
                </Screen>
              </div>
            </Fit>
          </Shot>
        </div>
      </div>
    </section>
  );
}
