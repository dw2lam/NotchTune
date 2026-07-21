import { useEffect, useState } from 'react';
import { Github } from 'lucide-react';
import GlassSurface from './GlassSurface';

const LINKS = [
  { label: 'FEATURES', href: '#features' },
  { label: 'MYSPACE', href: '#myspace' },
  { label: 'CUSTOMIZE', href: '#glass-lab' },
  { label: 'COMPARE', href: '#compare' },
  { label: 'DOWNLOAD', href: '#download' },
];

export default function Nav() {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 12);
    window.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  return (
    <header className={`nt-nav${scrolled ? ' scrolled' : ''}`}>
      <a className="nt-wordmark" href="#top">
        <img src="/assets/icon.png" alt="" />
        NotchTune
      </a>

      <GlassSurface
        width="auto"
        height="auto"
        borderRadius={999}
        className="nt-nav-glass"
        mixBlendMode="normal"
        brightness={58}
        opacity={0.92}
        blur={4}
        displace={0.4}
        distortionScale={-42}
        redOffset={0}
        greenOffset={4}
        blueOffset={8}
        backgroundOpacity={0.05}
        saturation={1.5}
      >
        <nav className="nt-navlinks">
          {LINKS.map((l) => (
            <a key={l.href} className="nt-navlink" href={l.href}>{l.label}</a>
          ))}
        </nav>
      </GlassSurface>

      <GlassSurface
        width="auto"
        height="auto"
        borderRadius={999}
        className="nt-nav-glass"
        mixBlendMode="normal"
        brightness={58}
        opacity={0.92}
        blur={4}
        displace={0.4}
        distortionScale={-42}
        redOffset={0}
        greenOffset={4}
        blueOffset={8}
        backgroundOpacity={0.05}
        saturation={1.5}
      >
        <a
          className="nt-navcta"
          href="https://github.com/dw2lam/NotchTune"
          target="_blank"
          rel="noopener"
        >
          <Github size={13} strokeWidth={1.8} />
          GITHUB
        </a>
      </GlassSurface>
    </header>
  );
}
