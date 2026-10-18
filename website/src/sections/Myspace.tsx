import { IslandPanel, MyspaceTab, MyspaceDropTarget, type MockThought } from '../mock';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { SecHead } from '../components/SecHead';

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
  const phone = usePhone();
  return (
    <section id="myspace" className="sec sec-paper" aria-labelledby="myspace-title">
      <div className="frame">
        <SecHead
          num="10" label="Myspace" note="Thoughts · Files · Reminders" id="myspace-title"
          title={<>A little space of your own.</>}
          lede="Jot a thought, drop a file on the notch to keep it close, and set reminders that nudge you from the top of the screen. It all stays on your Mac."
        />
        <div className="stage duo">
          <div className="edge reveal">
            <div className="hang at-start">
              <Shot label="The Myspace tab: a composer, filters, today's thoughts with an image attachment and a reminder for 9:00 AM.">
                <div className="zoom-shot">
                  <IslandPanel tab="myspace" glass="off" showNotchGap={!phone}>
                    <MyspaceTab thoughts={THOUGHTS} />
                  </IslandPanel>
                </div>
              </Shot>
            </div>
          </div>
          <div className="aside-stack reveal">
            <div className="edge">
              <span className="label">Drag a file to the notch</span>
              <Shot label="The notch's drop target: Throw anything in. Release to hold a copy in Myspace.">
                <div className="nt drop-card"><MyspaceDropTarget /></div>
              </Shot>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
