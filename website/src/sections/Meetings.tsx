import { IslandPanel, AgentsTab, ClosedPill, PixelSprite, type MockSession } from '../mock';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { SecHead } from '../components/SecHead';

const SESSIONS: MockSession[] = [
  {
    state: 'running', title: 'api · Make BridgeServer dispatch on a background queue',
    prompt: 'make BridgeServer dispatch on a background queue',
    activity: 'Running swift test --filter BridgeServerTests',
    agent: 'claude', terminal: 'Ghostty', age: '<1m',
  },
];

function VideoGlyph() {
  return <svg viewBox="0 0 16 16"><path d="M2 4.5h7.5c.6 0 1 .4 1 1v5c0 .6-.4 1-1 1H2c-.6 0-1-.4-1-1v-5c0-.6.4-1 1-1Zm9.5 2.3L15 5v6l-3.5-1.8Z" /></svg>;
}

/* The closed pill's meeting heads-up: title over the time, a call mark,
   the calendar's colour and the countdown. */
function MeetingPill({ phone }: { phone: boolean }) {
  return (
    <ClosedPill layout={phone ? 'pill' : 'notch'} mode={{ kind: 'live', char: 'dino', activity: { kind: 'working', title: '' } }}>
      <span className="nt-wing nt-wing-l">
        <PixelSprite char="dino" />
        <span className="mp-text"><b>Design review</b><em>21:29 – 21:59</em></span>
      </span>
      <span className={phone ? 'nt-pill-gap' : 'nt-pill-notchgap'} />
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
      <span className="meet-text"><b>Design review</b><span>In 4 min · 21:29 – 21:59</span></span>
      <span className="meet-join"><VideoGlyph /> Join</span>
      <span className="meet-x"><svg viewBox="0 0 16 16"><path d="M4.2 3.2 8 7l3.8-3.8 1 1L9 8l3.8 3.8-1 1L8 9l-3.8 3.8-1-1L7 8 3.2 4.2Z" /></svg></span>
    </div>
  );
}

export default function Meetings() {
  const phone = usePhone();
  return (
    <section id="meetings" className="sec sec-ink" aria-labelledby="meetings-title">
      <div className="frame">
        <SecHead
          num="07" label="Meetings" note="Opt-in · New in 2.1.5" id="meetings-title" flip
          title={<>Meetings, a few minutes early.</>}
          lede="The notch shows your next meeting with a countdown and a Join button for Zoom, Meet, Teams, Webex and FaceTime, and can keep NotchTune quiet while you’re in one. Your calendars never leave your Mac."
        />
        <div className="stage moments">
          <div className="moment reveal">
            <div className="moment-key">
              <span className="label"><i className="k-work" aria-hidden="true" />Closed</span>
              <p>Four minutes out, in the corner of your eye.</p>
            </div>
            <div className="moment-shot">
              <Shot label="The closed notch: Design review, 21:29 to 21:59, a video call, in 4 minutes.">
                <div className="zoom-pill"><MeetingPill phone={phone} /></div>
              </Shot>
            </div>
          </div>
          <div className="moment reveal">
            <div className="moment-key">
              <span className="label"><i className="k-done" aria-hidden="true" />Opened</span>
              <p>One click on Join, from the top of your Agents list.</p>
            </div>
            <div className="moment-shot">
              <Shot label="The opened island: a Design review banner with Join above the agent sessions.">
                <div className="zoom-shot">
                  <IslandPanel tab="agents" glass="off" showNotchGap={!phone}>
                    <MeetingBanner />
                    <AgentsTab sessions={SESSIONS} total={9} />
                  </IslandPanel>
                </div>
              </Shot>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
