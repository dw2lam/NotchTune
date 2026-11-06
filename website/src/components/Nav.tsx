const LINKS = [
  { label: 'Agents', href: '#agents' },
  { label: 'Music', href: '#music' },
  { label: 'Myspace', href: '#myspace' },
  { label: 'Mirror', href: '#mirror' },
  { label: 'Meetings', href: '#meetings' },
  { label: 'Personalize', href: '#personalize' },
];

export default function Nav({ section }: { section: string | null }) {
  return (
    <header className="nav">
      <div className="frame nav-in">
        <a className="brand" href="#top">
          <img src="/assets/icon.png" alt="" width={18} height={18} />
          NotchTune
        </a>
        <nav className="nav-links" aria-label="Features">
          {LINKS.map((l) => (
            <a key={l.href} href={l.href} aria-current={l.href === `#${section}` ? 'location' : undefined}>{l.label}</a>
          ))}
        </nav>
        <a className="nav-dl" href="#download">Download</a>
      </div>
    </header>
  );
}
