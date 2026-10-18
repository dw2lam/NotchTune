import type { CSSProperties } from 'react';
import { PixelPair } from '../components/PixelArt';
import { SecHead } from '../components/SecHead';

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
    <section id="characters" className="sec sec-paper" aria-labelledby="characters-title">
      <div className="frame">
        <SecHead
          num="08" label="Characters" note="20 to pick from" id="characters-title"
          title={<>Twenty little companions.</>}
          lede="A pixel friend lives in the notch. It rests while things are quiet, gets busy while your agents work, and raises a “!” when one needs you. From the dino and Claude’s Clawd to a goopy blob and a few Italian-brainrot favourites."
        />
        <div className="stage cast reveal">
          {CHARACTERS.map(([id, name], i) => (
            <figure className="cast-cell" key={id}>
              <div className="cast-tile" style={{ '--i': i } as CSSProperties}><PixelPair char={id} /></div>
              <figcaption>{name}<span>{String(i + 1).padStart(2, '0')}</span></figcaption>
            </figure>
          ))}
        </div>
        <div className="motions reveal">
          {MOTIONS.map((m) => (
            <div className={`motion m-${m.id}`} key={m.id}>
              <div className="motion-tile" aria-hidden="true"><PixelPair char="claude" /></div>
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
