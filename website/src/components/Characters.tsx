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
];

export default function Characters() {
  return (
    <section id="characters" className="section">
      <div className="section-head reveal">
        <h2>Pick your island buddy.</h2>
        <p>A tiny pixel companion lives in the notch: it blinks and fidgets at rest, gets busy while your agents work, and waves when a session needs you. Pick from ten.</p>
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
