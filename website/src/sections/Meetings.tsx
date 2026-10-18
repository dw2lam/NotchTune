import { Shot } from '../components/Shot';
import { Section, Bare } from '../components/Section';

function VideoGlyph() {
  return <svg viewBox="0 0 16 16"><path d="M2 4.5h7.5c.6 0 1 .4 1 1v5c0 .6-.4 1-1 1H2c-.6 0-1-.4-1-1v-5c0-.6.4-1 1-1Zm9.5 2.3L15 5v6l-3.5-1.8Z" /></svg>;
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
  return (
    <Section
      id="meetings" index="05" label="Meetings" flip
      title="Meetings, a few minutes early."
      line="An opt-in heads-up with Join, and quiet while you’re in a call. Your calendars never leave your Mac."
    >
      <div className="slab reveal">
        <div className="card">
          <div className="hang">
            <Shot label="The meeting heads-up in the island: Design review, in 4 minutes, 21:29 to 21:59, with Join.">
              <Bare><MeetingBanner /></Bare>
            </Shot>
          </div>
        </div>
      </div>
    </Section>
  );
}
