import type { CSSProperties } from 'react';
import { Sprite } from './Sprite';

const CHARS = [
  { char: 'dino', name: 'Dino', desc: 'The original. Sprints across your notch, tail flicking.', g1: '#2b7bff', g2: '#1f8f6a' },
  { char: 'ghost', name: 'Ghost', desc: 'Drifts while things are calm; glances around now and then.', g1: '#6b5cff', g2: '#241046' },
  { char: 'crab', name: 'Crab', desc: 'Scuttles sideways, claws clacking, waves both when you’re needed.', g1: '#ff6b6b', g2: '#a2240f' },
  { char: 'duck', name: 'Duck', desc: 'Waddles with a proper head bob and the odd quack.', g1: '#ffc24b', g2: '#c8760a' },
  { char: 'claude', name: 'Claude', desc: 'The Claude Code critter — walks with its spinner sparkle overhead.', g1: '#ff8c54', g2: '#7a2f0a' },
  { char: 'cat', name: 'Cat', desc: 'Kneads while agents work; ears twitch, tail swishes.', g1: '#f0a35e', g2: '#6b3a12' },
  { char: 'robot', name: 'Robot', desc: 'Antenna blinking, chest lights chasing while the job runs.', g1: '#5fb4c9', g2: '#1d4552' },
  { char: 'octopus', name: 'Octopus', desc: 'Swims in place, every tentacle rippling.', g1: '#d46bd8', g2: '#4b1450' },
  { char: 'frog', name: 'Frog', desc: 'Hops while busy, puffs its throat at rest.', g1: '#5bc46a', g2: '#1c5226' },
  { char: 'slime', name: 'Slime', desc: 'Squashes and stretches its way through every task.', g1: '#7be0b0', g2: '#1d6048' },
  { char: 'blob', name: 'Blob', desc: 'A happy mound of goo that drips, pools and jiggles while it works.', g1: '#ff9ad5', g2: '#6a1d58' },
  { char: 'poo', name: 'Poo', desc: 'Grins from the notch. Stink lines mean it’s working hard.', g1: '#c58a52', g2: '#4a2a12' },
  { char: 'johnPork', name: 'John Pork', desc: 'Roots around while agents run. When one needs you, John Pork is calling.', g1: '#ff9fb4', g2: '#7a2a3e' },
  { char: 'tungTung', name: 'Tung Tung', desc: 'Tung tung tung sahur: knocks its bat in time with your agents.', g1: '#d1a26a', g2: '#4e3216' },
  { char: 'tralalero', name: 'Tralalero', desc: 'A shark in sneakers, strutting in place while the job runs.', g1: '#4aa8ff', g2: '#0f3a6e' },
  { char: 'bombardiro', name: 'Bombardiro', desc: 'Crocodile bomber: propeller spinning, a bomb away every few seconds.', g1: '#8fbf63', g2: '#2c4a1e' },
  { char: 'ballerina', name: 'Ballerina', desc: 'Cappuccino-cup ballerina: passé at the barre, steam curling off the foam.', g1: '#f2b8d2', g2: '#6e3b2a' },
  { char: 'chimpanzini', name: 'Chimpanzini', desc: 'A chimp in a banana, flapping its peel and popping up when you’re needed.', g1: '#ffe066', g2: '#8a6a10' },
  { char: 'lirili', name: 'Lirilì', desc: 'The cactus elephant, swinging its pocket watch like a pendulum.', g1: '#a8d672', g2: '#3d5a1c' },
  { char: 'patapim', name: 'Patapim', desc: 'Brr brr: a leafy tree monkey that stomps its giant feet.', g1: '#7ccf5a', g2: '#3b2a14' },
];

export default function Characters() {
  return (
    <section id="characters" className="section">
      <div className="section-head reveal">
        <h2>Pick your island buddy.</h2>
        <p>A tiny pixel companion lives in the notch: it blinks and fidgets at rest, gets busy while your agents work, and waves when a session needs you. Pick from twenty.</p>
      </div>
      <div className="char-stage reveal">
        {CHARS.map((c) => (
          <article
            key={c.char}
            className="char-card glass"
            style={{ ['--g1' as string]: c.g1, ['--g2' as string]: c.g2 } as CSSProperties}
          >
            <div className="char-art">
              <div className="char-notch" />
              <Sprite char={c.char} />
            </div>
            <h4>{c.name}</h4>
            <p>{c.desc}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
