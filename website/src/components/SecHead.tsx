import type { ReactNode } from 'react';

/* Every section opens the same way: a ruled meta line (number, name, a
   note), then an oversized title against a short lede. */
export function SecHead({ num, label, note, id, title, lede, flip = false }: {
  num: string;
  label: string;
  note?: string;
  id: string;
  title: ReactNode;
  lede: ReactNode;
  flip?: boolean;
}) {
  return (
    <>
      <div className="sec-meta reveal">
        <span className="num">{num}</span>
        <span className="label">{label}</span>
        {note && <span className="label">{note}</span>}
      </div>
      <div className={`sec-head reveal${flip ? ' flip' : ''}`}>
        <h2 id={id} className="title">{title}</h2>
        <p className="lede">{lede}</p>
      </div>
    </>
  );
}
