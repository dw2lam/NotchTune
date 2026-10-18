import { Download } from 'lucide-react';
import { useLatestRelease } from '../hooks/useLatestRelease';

const LINKS = [
  { label: 'Agents', href: '#agents' },
  { label: 'Music', href: '#music' },
  { label: 'Meetings', href: '#meetings' },
  { label: 'Characters', href: '#characters' },
  { label: 'Personalize', href: '#personalize' },
];

export default function Nav() {
  const { downloadUrl } = useLatestRelease();
  return (
    <header className="nav">
      <a className="wordmark" href="#top" aria-label="NotchTune home">
        <img src="/assets/icon.png" alt="" width={26} height={26} />
        NotchTune
      </a>
      <nav className="nav-links" aria-label="Sections">
        {LINKS.map((l) => <a key={l.href} href={l.href}>{l.label}</a>)}
      </nav>
      <a className="btn btn-primary btn-sm" href={downloadUrl}>
        <Download aria-hidden="true" strokeWidth={2.2} />
        Download
      </a>
    </header>
  );
}
