import type { CSSProperties } from 'react';
import { Sprite } from './Sprite';

const CHARS = [
  { char: 'dino', name: 'Dino', desc: 'The original. Sprints across your notch, tail high.', g1: '#2b7bff', g2: '#1f8f6a' },
  { char: 'ghost', name: 'Ghost', desc: 'Cool and quiet — drifts gently while things are calm.', g1: '#6b5cff', g2: '#241046' },
  { char: 'crab', name: 'Crab', desc: 'Sidesteps along the island, claws clacking.', g1: '#ff6b6b', g2: '#a2240f' },
  { char: 'duck', name: 'Duck', desc: 'Paddles past; flaps a wing when an agent moves.', g1: '#ffc24b', g2: '#c8760a' },
  { char: 'claude', name: 'Claude', desc: 'A little friend for the Claude Code crowd.', g1: '#ff8c54', g2: '#7a2f0a' },
];

export default function Characters() {
  return (
    <section id="characters" className="section">
      <div className="section-head reveal">
        <h2>Pick your island buddy.</h2>
        <p>A tiny pixel companion bounces out of the notch while it idles — and jumps when a session needs you. Choose the one that fits your setup.</p>
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
