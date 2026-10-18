import { IslandPanel, MusicTab, ClosedPill } from '../mock';
import { PrevIcon, NextIcon, PauseIcon } from '../mock/icons';
import { Fit } from '../components/Fit';
import { Shot } from '../components/Shot';
import { Screen } from '../components/Screen';

const ART = '/assets/submarine.jpg';

export default function Music() {
  return (
    <section id="music" className="section" aria-labelledby="music-title">
      <div className="wrap">
        <header className="head">
          <p className="eyebrow reveal">Music</p>
          <h2 id="music-title" className="h2 reveal d1">What’s playing, right where you&nbsp;look.</h2>
          <p className="lede reveal d2">
            Spotify and Apple Music live in the notch: a tiny cover and waveform while you work, the full player
            one hover away, a two-finger swipe to skip, and your library to browse without leaving the song you’re on.
          </p>
        </header>

        <div className="layered reveal">
          <div className="stage glass">
            <Shot label="The Music tab under the notch: Sienna by The Marías, playing, with shuffle, previous, pause, next, repeat and a progress bar.">
              <Fit width={1000}>
                <Screen height={300} app="Music">
                  <IslandPanel tab="music" ambientArt={ART} glass="off">
                    <MusicTab
                      track={{ title: 'Sienna', artist: 'The Marías', art: `url(${ART})`, duration: 218 }}
                      playing
                      position={64}
                    />
                  </IslandPanel>
                </Screen>
              </Fit>
            </Shot>
          </div>

          <div className="float-card glass-soft" style={{ left: -18, bottom: -46, ['--w' as string]: '374px' }}>
            <span className="fc-label">While you work</span>
            <Shot label="The closed notch showing the album cover on the left and a waveform on the right.">
              <Fit width={340}>
                <Screen slice minimal app="Music">
                  <ClosedPill layout="notch" mode={{ kind: 'music-compact', art: ART, playing: true }} />
                </Screen>
              </Fit>
            </Shot>
          </div>

          <div className="float-card glass-soft" style={{ right: -18, bottom: -64, ['--w' as string]: '210px' }}>
            <span className="fc-label">Hover a cover in your library</span>
            <Shot label="The Now Playing cover in the library with tiny controls: progress, previous, pause and next.">
              <div className="np-tile" style={{ backgroundImage: `url(${ART})` }}>
                <span className="np-expand"><svg viewBox="0 0 12 12"><path d="M7 1.5h3.5V5M5 10.5H1.5V7M10.5 1.5 7 5M1.5 10.5 5 7" /></svg></span>
                <div className="np-mini">
                  <b>Sienna</b>
                  <div className="np-bar"><i /></div>
                  <div className="np-ctl">
                    <PrevIcon />
                    <span className="play"><PauseIcon /></span>
                    <NextIcon />
                  </div>
                </div>
              </div>
            </Shot>
          </div>
        </div>
      </div>
    </section>
  );
}

