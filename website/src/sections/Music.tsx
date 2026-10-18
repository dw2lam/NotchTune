import { Shot } from '../components/Shot';
import { Feature, Crop } from '../components/Feature';

export default function Music() {
  return (
    <Feature
      id="music" layout="flip"
      title="Music without switching apps."
      line="Spotify or Apple Music, right under the notch: the cover, the controls, and a two-finger swipe to skip."
    >
      <Crop x={206}>
        <Shot
          name="player" className="lift"
          alt="The Music tab under the notch, playing Still Water by Juniper Coast at 1:21 of 3:56, with shuffle, previous, pause, next and repeat."
        />
      </Crop>
    </Feature>
  );
}
