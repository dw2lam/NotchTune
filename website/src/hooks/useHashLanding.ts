import { useLayoutEffect } from 'react';

// The browser looks for a #fragment before React has rendered it, finds
// nothing and stays at the top, so look again once the page exists. A position
// the browser has already restored (a reload, Back) is left alone.
export function useHashLanding() {
  useLayoutEffect(() => {
    const id = location.hash.slice(1);
    if (id && scrollY === 0) document.getElementById(id)?.scrollIntoView();
  }, []);
}
