/* The moonlit oasis (generated with Antigravity), used as framed plates:
   always with its real size set so nothing shifts, the large file only for
   wide or dense screens, lazy unless it is the hero. Decorative. */
const SRC = '/assets/oasis-night-1376.webp';
const SRC_SET = '/assets/oasis-night-1376.webp 1376w, /assets/oasis-night-2752.webp 2752w';

export function PlateImage({ sizes = '100vw', eager = false }: { sizes?: string; eager?: boolean }) {
  return (
    <img
      className="plate-img"
      src={SRC}
      srcSet={SRC_SET}
      sizes={sizes}
      width={2752}
      height={1536}
      alt=""
      decoding="async"
      loading={eager ? 'eager' : 'lazy'}
      {...(eager ? { fetchpriority: 'high' } : {})}
    />
  );
}
