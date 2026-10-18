import { useEffect, useRef, type ReactNode } from 'react';

/* A product shot is a picture, not a control: the mock kit inside it keeps
   its real buttons for fidelity, so the whole subtree is made inert (no
   focus, no clicks) and described once for assistive tech. */
export function Shot({ label, children, className = '' }: { label: string; children: ReactNode; className?: string }) {
  const inner = useRef<HTMLDivElement>(null);
  useEffect(() => {
    inner.current?.setAttribute('inert', '');
  }, []);
  return (
    <figure className={`shot ${className}`.trim()} role="img" aria-label={label}>
      <div ref={inner} className="shot-inner" aria-hidden="true">{children}</div>
    </figure>
  );
}
