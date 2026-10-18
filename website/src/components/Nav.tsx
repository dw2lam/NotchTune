import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';

const LINKS = [
  { n: '02', label: 'Notch', href: '#agents' },
  { n: '03', label: 'Summaries', href: '#summaries' },
  { n: '04', label: 'Music', href: '#music' },
  { n: '05', label: 'Meetings', href: '#meetings' },
  { n: '06', label: 'Personalize', href: '#personalize' },
];

export default function Nav() {
  const { downloadUrl } = useLatestRelease();
  return (
    <header className="nav">
      <div className="frame nav-inner">
        <a className="wordmark" href="#top" aria-label="NotchTune home">
          <img src="/assets/icon.png" alt="" width={22} height={22} />
          NotchTune
        </a>
        <nav className="nav-links" aria-label="Sections">
          {LINKS.map((l) => <a key={l.href} href={l.href}><span>{l.n}</span>{l.label}</a>)}
        </nav>
        <a className="btn btn-primary btn-sm" href={downloadUrl}>
          <Download aria-hidden="true" strokeWidth={2.4} />
          Download
        </a>
      </div>
    </header>
  );
}
