import { useState } from 'react';
import {
  MyspaceTab, RemindersTab, MyspaceDropTarget, ClipsList,
  type MockThought, type MockReminder, type MockClip,
} from '../mock';

const SECTION_CLIPS: MockClip[] = [
  { kind: 'link', preview: 'https://notchtune.dev/download', time: '4:41 PM' },
  { kind: 'text', preview: 'const glass = resolve(.clear, tint: 0.22)', time: '4:38 PM' },
  { kind: 'image', preview: 'Screenshot 2026-07-20', time: '4:12 PM', art: 'linear-gradient(135deg,#2c5f2d,#97bc62)' },
  { kind: 'file', preview: 'NotchTune.dmg', time: '3:58 PM' },
];

/* The Myspace feature section — a personal space living in the notch.
   (Yes, that Myspace. Sort of.) */

const SECTION_THOUGHTS: MockThought[] = [
  {
    text: 'hero art for the launch post',
    time: '4:12:08 PM',
    attachments: [{ name: 'launch-hero@2x.png', ext: 'png', kind: 'image', art: 'linear-gradient(135deg,#1f3b73,#3c79b8 55%,#9fd0e8)' }],
  },
  { text: 'idea: the pill should lean toward a file you drag near it', time: '2:03:41 PM' },
  { text: 'ship the notch update tonight', time: '1:47:12 PM', reminderAt: 'Jul 21, 9:00 AM' },
];

const SECTION_REMINDERS: MockReminder[] = [
  { text: 'Reply to the App Store review', reminderAt: 'Jul 21, 9:30 AM', created: '4:02:11 PM' },
  { text: 'Water the monstera', created: '1:38:52 PM' },
  { text: 'Send the beta build to Sam', reminderAt: 'Jul 20, 5:00 PM', created: '11:14:27 AM', done: true },
];

export default function Myspace() {
  const [thoughts, setThoughts] = useState(SECTION_THOUGHTS);
  const [reminders, setReminders] = useState(SECTION_REMINDERS);

  return (
    <section id="myspace" className="section">
      <div className="section-head reveal">
        <h2>Remember MySpace? We brought it back. Sort&nbsp;of.</h2>
        <p>
          No profile songs, no glitter GIFs, no ranking your friends. Myspace is a
          tiny personal space that lives in your notch — throw files at it, jot
          thoughts, set reminders. Everything stays on your Mac. Tom would be proud.
        </p>
      </div>

      {/* File shelf — the drop target close-up */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">File shelf</span>
          <h3>Throw anything in.</h3>
          <p>
            Drag a file toward the notch and the pill leans in to catch it — it
            only opens once you actually arrive. Release, and a copy is held in
            Myspace: screenshots on their way somewhere, assets you'll need in an
            hour, that PDF you'll definitely read later.
          </p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/sonoma.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(440px, 100%)', transform: 'scale(1.06)' }}>
              <MyspaceDropTarget />
            </div>
          </div>
        </div>
      </div>

      {/* Thoughts — composer + rows */}
      <div className="feature feature-rev reveal">
        <div className="feature-text">
          <span className="kicker">Thoughts</span>
          <h3>A scratchpad that's already open.</h3>
          <p>
            Drop a thought in without switching apps — type it or pin a file to
            it. Everything lands in a quiet, day-grouped stream you can skim
            later. Local-first: your space never leaves your machine.
          </p>
          <p className="feature-aside">Go on, try the composer →</p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/purple.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(470px, 100%)' }}>
              <MyspaceTab
                thoughts={thoughts}
                onSubmit={(text) => setThoughts((t) => [
                  { text, time: new Date().toLocaleTimeString() }, ...t,
                ])}
                onDelete={(i) => setThoughts((t) => t.filter((_, idx) => idx !== i))}
              />
            </div>
          </div>
        </div>
      </div>

      {/* Clipboard history */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Clipboard</span>
          <h3>Everything you copy. One glance up.</h3>
          <p>
            Flip it on and Myspace keeps your clipboard history — text, links,
            images, and files land in the Clips list the moment you copy them.
            Off by default: your pasteboard is yours. Click to
            copy back, drag straight into any app. Local-only, skips password
            managers, and cleans up after itself in three days.
          </p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/orange.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(470px, 100%)' }}>
              <ClipsList clips={SECTION_CLIPS} />
            </div>
          </div>
        </div>
      </div>

      {/* Reminders — active/archive */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Reminders</span>
          <h3>Nudges from the notch.</h3>
          <p>
            Turn any thought into a reminder — timed ones notify you, untimed ones
            just wait patiently. Check one off and it moves to the archive instead
            of vanishing, so "done" still has a paper trail.
          </p>
          <p className="feature-aside">
            Unlike your old MySpace page, this one you'll actually check.
          </p>
        </div>
        <div className="feature-stage">
          <div className="nt nt-stage" style={{ backgroundImage: 'url(/assets/wallpapers/green.jpg)' }}>
            <div className="nt-fragment nt-zoom" style={{ width: 'min(470px, 100%)' }}>
              <RemindersTab
                reminders={reminders}
                onToggle={(i) => setReminders((r) => r.map(
                  (item, idx) => (idx === i ? { ...item, done: !item.done } : item),
                ))}
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
