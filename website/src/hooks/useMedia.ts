import { useEffect, useState } from 'react';

// A media query read synchronously on first render (this is a client-only
// page), so phone-specific compositions never flash the desktop layout.
export function useMedia(query: string): boolean {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const mql = window.matchMedia(query);
    const onChange = () => setMatches(mql.matches);
    onChange();
    mql.addEventListener('change', onChange);
    return () => mql.removeEventListener('change', onChange);
  }, [query]);
  return matches;
}

/** Phones get their own crops: the island without the notch gap, the
    external-display pill instead of the MacBook wings. */
export const usePhone = () => useMedia('(max-width: 599px)');
