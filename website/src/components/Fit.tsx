import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';

/* Product shots are drawn at the app's real size (pt = px) on a fixed-width
   canvas, then scaled down to fit narrower screens — so they stay faithful
   and never cause horizontal scrolling. */
export function Fit({ width, children, className = '' }: { width: number; children: ReactNode; className?: string }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const [height, setHeight] = useState<number>();

  useLayoutEffect(() => {
    const o = outer.current;
    const i = inner.current;
    if (!o || !i) return;
    const measure = () => {
      const s = Math.min(1, o.clientWidth / width);
      setScale(s);
      setHeight(i.offsetHeight * s);
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(o);
    ro.observe(i);
    return () => ro.disconnect();
  }, [width]);

  return (
    <div ref={outer} className={`fit ${className}`.trim()} style={{ height }}>
      <div ref={inner} className="fit-inner" style={{ width, transform: `translateX(-50%) scale(${scale})` }}>
        {children}
      </div>
    </div>
  );
}
