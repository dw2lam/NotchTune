import { SPRITES, SPRITES_RUN, spriteSVG } from '../lib/sprites';

/* One of the app's pixel characters, from the generated sprite data. `frame`
   picks the resting pose or the working pose. Decorative: callers label it. */
export function PixelArt({ char, frame = 'rest' }: { char: string; frame?: 'rest' | 'run' }) {
  const grid = (frame === 'run' ? SPRITES_RUN[char] : undefined) ?? SPRITES[char];
  if (!grid) return null;
  return <span className={`px ${frame}`} aria-hidden="true" dangerouslySetInnerHTML={{ __html: spriteSVG(grid) }} />;
}

/* Both poses stacked, for CSS to alternate between. */
export function PixelPair({ char }: { char: string }) {
  return (
    <>
      <PixelArt char={char} frame="rest" />
      <PixelArt char={char} frame="run" />
    </>
  );
}
