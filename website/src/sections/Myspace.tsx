import { IslandPanel, MyspaceTab, MyspaceDropTarget, type MockThought } from '../mock';
import { Fit } from '../components/Fit';
import { Shot } from '../components/Shot';
import { Screen } from '../components/Screen';

const THOUGHTS: MockThought[] = [
  {
    text: 'hero art for the launch post',
    time: '4:12:08 PM',
    attachments: [{ name: 'launch-hero@2x.png', ext: 'png', kind: 'image', art: 'linear-gradient(135deg,#123a5c,#2f7d9a 55%,#9fd8e0)' }],
  },
  { text: 'idea: the pill should lean toward a file you drag near it', time: '2:03:41 PM' },
  { text: 'ship the notch update tonight', time: '1:47:12 PM', reminderAt: 'Oct 18, 9:00 AM' },
];

export default function Myspace() {
  return (
    <section id="myspace" className="section" aria-labelledby="myspace-title">
      <div className="wrap">
        <header className="head">
          <p className="eyebrow reveal">Myspace</p>
          <h2 id="myspace-title" className="h2 reveal d1">A little space of your&nbsp;own.</h2>
          <p className="lede reveal d2">
            Jot a thought, drop a file on the notch to keep it close, and set reminders that nudge you from the top
            of the screen. It all stays on your Mac.
          </p>
        </header>

        <div className="layered reveal">
          <div className="stage glass">
            <Shot label="The Myspace tab: a composer, filters, today's thoughts with an image attachment and a reminder for 9:00 AM.">
              <Fit width={1000}>
                <Screen height={470} app="Finder">
                  <IslandPanel tab="myspace" glass="off">
                    <MyspaceTab thoughts={THOUGHTS} />
                  </IslandPanel>
                </Screen>
              </Fit>
            </Shot>
          </div>
          <div className="float-card glass-soft" style={{ right: -18, bottom: -48, ['--w' as string]: '334px' }}>
            <span className="fc-label">Drag a file to the notch</span>
            <Shot label="The notch's drop target: Throw anything in. Release to hold a copy in Myspace.">
              <Fit width={300}>
                <div className="nt" style={{ width: 300, borderRadius: 16, overflow: 'hidden', background: '#000' }}>
                  <MyspaceDropTarget />
                </div>
              </Fit>
            </Shot>
          </div>
        </div>
      </div>
    </section>
  );
}
