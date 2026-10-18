/* A real capture of NotchTune (website/public/assets/shots, made with the
   app's headless harness at 2x). Drawn at the app's own size; on a phone a
   wide shot is cropped to a window rather than shrunk. */
export const SHOTS = {
  island: { w: 650, h: 354 },
  'pill-working': { w: 468, h: 38 },
  'pill-waiting': { w: 488, h: 38 },
  'pill-finished': { w: 492, h: 38 },
  'pill-meeting': { w: 464, h: 38 },
  summary: { w: 550, h: 172 },
  player: { w: 650, h: 203 },
  banner: { w: 650, h: 75 },
  settings: { w: 902, h: 1212 },
} as const;

export function Shot({ name, alt, eager = false, className = '' }: {
  name: keyof typeof SHOTS; alt: string; eager?: boolean; className?: string;
}) {
  const { w, h } = SHOTS[name];
  const src = `/assets/shots/${name}.webp`;
  return (
    <img
      className={`shot shot-${name} ${className}`.trim()}
      src={src}
      srcSet={`${src} 2x`}
      width={w}
      height={h}
      alt={alt}
      decoding="async"
      loading={eager ? 'eager' : 'lazy'}
      {...(eager ? { fetchpriority: 'high' } : {})}
    />
  );
}
