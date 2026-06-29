import { useEffect, useRef, useState, type RefObject } from 'react';

// Cycles through `order` every `intervalMs`, pausing while `ref` is offscreen.
// Honors prefers-reduced-motion by staying on the first entry.
export function useCycle(
  order: string[],
  intervalMs: number,
  ref: RefObject<HTMLElement | null>
): string {
  const [current, setCurrent] = useState(order[0]);
  const idx = useRef(0);

  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    let running = true;
    const timer = window.setInterval(() => {
      if (!running) return;
      idx.current = (idx.current + 1) % order.length;
      setCurrent(order[idx.current]);
    }, intervalMs);

    let io: IntersectionObserver | undefined;
    if (ref.current) {
      io = new IntersectionObserver(
        (entries) => entries.forEach((e) => { running = e.isIntersecting; }),
        { threshold: 0.3 }
      );
      io.observe(ref.current);
    }
    return () => {
      window.clearInterval(timer);
      io?.disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return current;
}
