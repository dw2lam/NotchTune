import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';

const LINKS = [
  { n: '02', label: 'Agents', href: '#agents' },
  { n: '06', label: 'Music', href: '#music' },
  { n: '07', label: 'Meetings', href: '#meetings' },
  { n: '08', label: 'Characters', href: '#characters' },
  { n: '09', label: 'Personalize', href: '#personalize' },
];

export default function Nav() {
  const { downloadUrl } = useLatestRelease();
  return (
    <header className="nav">
      <div className="frame nav-inner">
        <a className="wordmark" href="#top" aria-label="NotchTune home">
          <img src="/assets/icon.png" alt="" width={26} height={26} />
          NotchTune
        </a>
        <nav className="nav-links" aria-label="Sections">
          {LINKS.map((l) => <a key={l.href} href={l.href}><span>{l.n}</span>{l.label}</a>)}
        </nav>
        <a className="btn btn-solid btn-sm" href={downloadUrl}>
          <Download aria-hidden="true" strokeWidth={2.2} />
          Download
        </a>
      </div>
    </header>
  );
}
