import { useReveal } from './hooks/useReveal';
import Backdrop from './components/Backdrop';
import Nav from './components/Nav';
import Footer from './components/Footer';
import Hero from './sections/Hero';
import Agents from './sections/Agents';
import Approvals from './sections/Approvals';
import Summaries from './sections/Summaries';
import WorksWith from './sections/WorksWith';
import Music from './sections/Music';
import Meetings from './sections/Meetings';
import Characters from './sections/Characters';
import Personalization from './sections/Personalization';
import Myspace from './sections/Myspace';
import Details from './sections/Details';
import Download from './sections/Download';

export default function App() {
  useReveal();
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>
      <Backdrop />
      <Nav />
      <main id="main">
        <span id="top" />
        <Hero />
        <Agents />
        <Approvals />
        <Summaries />
        <WorksWith />
        <Music />
        <Meetings />
        <Characters />
        <Personalization />
        <Myspace />
        <Details />
        <Download />
      </main>
      <Footer />
    </>
  );
}
