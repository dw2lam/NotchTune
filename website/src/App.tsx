import { useReveal } from './hooks/useReveal';
import Nav from './components/Nav';
import Footer from './components/Footer';
import Hero from './sections/Hero';
import Agents from './sections/Agents';
import Summaries from './sections/Summaries';
import Music from './sections/Music';
import Meetings from './sections/Meetings';
import Personalization from './sections/Personalization';
import Download from './sections/Download';

export default function App() {
  useReveal();
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>
      <Nav />
      <main id="main">
        <span id="top" />
        <div className="band">
          <Hero />
          <Agents />
        </div>
        <div className="band band-light">
          <Summaries />
          <Music />
        </div>
        <div className="band">
          <Meetings />
        </div>
        <div className="band band-light">
          <Personalization />
        </div>
        <Download />
      </main>
      <Footer />
    </>
  );
}
