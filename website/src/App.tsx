import { useState } from 'react';
import { useHashLanding } from './hooks/useHashLanding';
import { useReveal } from './hooks/useReveal';
import Nav from './components/Nav';
import Footer from './components/Footer';
import Story from './sections/Story';
import Download from './sections/Download';

export default function App() {
  const [section, setSection] = useState<string | null>(null);
  useReveal();
  useHashLanding();
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>
      <Nav section={section} />
      <main id="main">
        <span id="top" />
        <Story onSection={setSection} />
        <Download />
      </main>
      <Footer />
    </>
  );
}
