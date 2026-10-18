import type { CSSProperties, ReactNode } from 'react';

/* One feature: a headline and one sentence on the left edge, the real
   capture beside or below them. */
export function Feature({ id, title, line, layout = 'side', children }: {
  id: string; title: ReactNode; line: ReactNode; layout?: 'side' | 'flip' | 'below' | 'wide'; children: ReactNode;
}) {
  return (
    <section id={id} className={`feature feature-${layout}`} aria-labelledby={`${id}-title`}>
      <div className="frame feature-in">
        <div className="feature-text reveal">
          <h2 id={`${id}-title`} className="h2">{title}</h2>
          <p className="lede">{line}</p>
        </div>
        <div className="feature-stage reveal">{children}</div>
      </div>
    </section>
  );
}

/* On a phone, a window onto a wide shot at its real size: `x` is where the
   window starts (CSS px into the shot), or `to` where it ends; `h` an
   optional height to stop at. */
export function Crop({ x = 0, to, h, children }: { x?: number; to?: number; h?: number; children: ReactNode }) {
  const style = {
    '--x': `${x}px`,
    ...(to ? { '--to': `${to}px` } : {}),
    ...(h ? { '--h': `${h}px` } : {}),
  } as CSSProperties;
  const mid = x || to;
  return <div className={`crop${mid ? ' crop-mid' : ''}${to ? ' crop-to' : ''}${h ? ' crop-cut' : ''}`} style={style}>{children}</div>;
}
