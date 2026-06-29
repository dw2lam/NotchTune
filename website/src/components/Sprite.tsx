import { SPRITES, SPRITES_RUN, spriteSVG } from '../lib/sprites';

// Static idle pixel sprite (characters gallery + compact-notch idle slot).
export function Sprite({ char, className = '' }: { char: string; className?: string }) {
  const grid = SPRITES[char];
  if (!grid) return null;
  return (
    <span
      className={`sprite ${className}`.trim()}
      role="img"
      aria-label={`${char} pixel sprite`}
      dangerouslySetInnerHTML={{ __html: spriteSVG(grid) }}
    />
  );
}

// Animated run-cycle "dance" used when agents are live (idle + run frames).
export function SpriteRun({ char, className = '' }: { char: string; className?: string }) {
  const idle = SPRITES[char];
  const run = SPRITES_RUN[char];
  if (!idle || !run) return null;
  const html =
    `<span class="frA">${spriteSVG(idle)}</span>` +
    `<span class="frB">${spriteSVG(run)}</span>`;
  return (
    <span
      className={`sprite sprite-run ${className}`.trim()}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
