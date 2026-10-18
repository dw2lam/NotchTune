import { MusicTab } from '../mock';
import { Shot } from '../components/Shot';
import { Section, Bare } from '../components/Section';

const ART = '/assets/submarine.jpg';

export default function Music() {
  return (
    <Section
      id="music" index="04" label="Music"
      title="Music without switching apps."
      line="Spotify or Apple Music, with the cover, the controls and a two-finger swipe to skip."
    >
      <div className="slab reveal">
        <div className="card">
          <div className="hang">
            <Shot label="The player in the island: Sienna by The Marías, playing, with shuffle, previous, pause, next, repeat and a progress bar.">
              <Bare art={ART}>
                <MusicTab track={{ title: 'Sienna', artist: 'The Marías', art: `url(${ART})`, duration: 218 }} playing position={64} />
              </Bare>
            </Shot>
          </div>
        </div>
      </div>
    </Section>
  );
}
