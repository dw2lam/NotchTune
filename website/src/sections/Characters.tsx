import type { CSSProperties } from 'react';
import { PixelPair } from '../components/PixelArt';

/* The app's twenty characters, in its picker order. */
const CHARACTERS: [string, string][] = [
  ['dino', 'Dino'], ['ghost', 'Ghost'], ['crab', 'Crab'], ['duck', 'Duck'], ['claude', 'Claude'],
  ['cat', 'Cat'], ['robot', 'Robot'], ['octopus', 'Octopus'], ['frog', 'Frog'], ['slime', 'Slime'],
  ['blob', 'Blob'], ['poo', 'Poo'], ['johnPork', 'John Pork'], ['tungTung', 'Tung Tung'], ['tralalero', 'Tralalero'],
  ['bombardiro', 'Bombardiro'], ['ballerina', 'Ballerina'], ['chimpanzini', 'Chimpanzini'], ['lirili', 'Lirilì'], ['patapim', 'Patapim'],
];

const MOTIONS = [
  { id: 'calm', title: 'Calm', text: 'The default. Still, with the odd blink or glance.' },
  { id: 'lively', title: 'Lively', text: 'Hops, walk cycles and little fidgets.' },
  { id: 'still', title: 'Still', text: 'One pose for each state, nothing more.' },
];

export default function Characters() {
  return (
    <section id="characters" className="section" aria-labelledby="characters-title">
      <div className="wrap">
        <header className="head">
          <p className="eyebrow reveal">Characters</p>
          <h2 id="characters-title" className="h2 reveal d1">Twenty little companions.</h2>
          <p className="lede reveal d2">
            A pixel friend lives in the notch. It rests while things are quiet, gets busy while your agents work,
            and raises a “!” when one needs you. Pick from twenty, from the dino and Claude’s Clawd to a goopy
            blob and a few Italian-brainrot favourites.
          </p>
        </header>

        <div className="chars glass reveal">
          <div className="char-grid">
            {CHARACTERS.map(([id, name], i) => (
              <figure className="char" key={id}>
                <div className="char-tile" style={{ '--i': i } as CSSProperties}>
                  <PixelPair char={id} />
                </div>
                <figcaption>{name}</figcaption>
              </figure>
            ))}
          </div>
        </div>

        <div className="motions">
          {MOTIONS.map((m) => (
            <div className={`motion glass-soft reveal m-${m.id}`} key={m.id}>
              <div className="motion-tile"><PixelPair char="claude" /></div>
              <div>
                <h3>{m.title}</h3>
                <p>{m.text}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
