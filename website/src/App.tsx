import { useReveal } from './hooks/useReveal';
import Nav from './components/Nav';
import Footer from './components/Footer';
import Story from './sections/Story';
import Download from './sections/Download';

export default function App() {
  useReveal();
  return (
    <>
      <a className="skip-link" href="#main">Skip to content</a>
      <Nav />
      <main id="main">
        <span id="top" />
        <Story />
        <Download />
      </main>
      <Footer />
    </>
  );
}
