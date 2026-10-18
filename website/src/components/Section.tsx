import type { ReactNode } from 'react';

/* A feature on the grid: a ruled index bar, one headline and one line on a
   few columns, its index number set large behind the glass, and the glass
   itself. `flip` puts the text on the right; `wide` puts the glass under
   the text across all twelve columns. */
export function Section({ id, index, label, title, line, flip = false, wide = false, children }: {
  id: string; index: string; label: string; title: ReactNode; line: ReactNode;
  flip?: boolean; wide?: boolean; children: ReactNode;
}) {
  return (
    <section id={id} className={`sec${flip ? ' flip' : ''}${wide ? ' wide' : ''}`} aria-labelledby={`${id}-title`}>
      <div className="frame">
        <p className="bar"><span>{index}</span>{label}</p>
        <div className="sec-body">
          <div className="sec-text reveal">
            <h2 id={`${id}-title`} className="h2">{title}</h2>
            <p className="sub">{line}</p>
          </div>
          <span className="sec-index" aria-hidden="true">{index}</span>
          <div className="stage">{children}</div>
        </div>
      </div>
    </section>
  );
}

/* The island's body without its header: a detail of the opened island,
   for features that live inside it. */
export function Bare({ art, children }: { art?: string; children: ReactNode }) {
  return (
    <div className="nt nt-island nt-bare">
      {art && <div className="nt-ambient" style={{ backgroundImage: `url(${art})` }} />}
      {children}
    </div>
  );
}
