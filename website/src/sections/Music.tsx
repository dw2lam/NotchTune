import { IslandPanel, MusicTab, ClosedPill } from '../mock';
import { PrevIcon, NextIcon, PauseIcon } from '../mock/icons';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { SecHead } from '../components/SecHead';

const ART = '/assets/submarine.jpg';

export default function Music() {
  const phone = usePhone();
  return (
    <section id="music" className="sec sec-night" aria-labelledby="music-title">
      <div className="frame">
        <SecHead
          num="06" label="Music" note="Spotify · Apple Music" id="music-title"
          title={<>What’s playing, right where you look.</>}
          lede="A tiny cover and waveform while you work, the full player one hover away, a two-finger swipe to skip, and your library to browse without leaving the song you’re on."
        />
        <div className="stage duo">
          <div className="edge reveal">
            <div className="hang at-start">
              <Shot label="The Music tab under the notch: Sienna by The Marías, playing, with shuffle, previous, pause, next, repeat and a progress bar.">
                <div className="zoom-shot">
                  <IslandPanel tab="music" ambientArt={ART} glass="off" showNotchGap={!phone}>
                    <MusicTab track={{ title: 'Sienna', artist: 'The Marías', art: `url(${ART})`, duration: 218 }} playing position={64} />
                  </IslandPanel>
                </div>
              </Shot>
            </div>
          </div>
          <div className="aside-stack reveal">
            <div className="edge">
              <span className="label">Closed, while you work</span>
              <Shot label="The closed notch showing the album cover and a waveform.">
                <div className="zoom-pill">
                  <ClosedPill layout={phone ? 'pill' : 'notch'} mode={{ kind: 'music-compact', art: ART, playing: true }} />
                </div>
              </Shot>
            </div>
            <div className="edge">
              <span className="label">Hover a cover in your library</span>
              <Shot label="The Now Playing cover in the library with tiny controls: progress, previous, pause and next.">
                <div className="np-tile" style={{ backgroundImage: `url(${ART})` }}>
                  <span className="np-expand"><svg viewBox="0 0 12 12"><path d="M7 1.5h3.5V5M5 10.5H1.5V7M10.5 1.5 7 5M1.5 10.5 5 7" /></svg></span>
                  <div className="np-mini">
                    <b>Sienna</b>
                    <div className="np-bar"><i /></div>
                    <div className="np-ctl"><PrevIcon /><span className="play"><PauseIcon /></span><NextIcon /></div>
                  </div>
                </div>
              </Shot>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
