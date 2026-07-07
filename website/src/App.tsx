import { useReveal } from './hooks/useReveal';
import LightRays from './components/LightRays';
import Nav from './components/Nav';
import Hero from './components/Hero';
import Demo from './components/Demo';
import Features from './components/Features';
import Characters from './components/Characters';
import Personalize from './components/Personalize';
import Compare from './components/Compare';
import Download from './components/Download';
import Footer from './components/Footer';

export default function App() {
  useReveal();

  return (
    <>
      {/* black backdrop */}
      <div className="ambient" aria-hidden="true">
        <div className="grain" />
      </div>

      {/* WebGL light rays (above the black, behind content) */}
      <LightRays
        raysOrigin="top-center"
        raysColor="#9db8ff"
        raysSpeed={1.0}
        lightSpread={0.55}
        rayLength={2.4}
        followMouse
        mouseInfluence={0.1}
        noiseAmount={0.06}
        distortion={0.03}
        fadeDistance={1.6}
        saturation={1.0}
      />

      <Nav />

      <main id="top">
        <Hero />
        <Demo />
        <Features />
        <Characters />
        <Personalize />
        <Compare />
        <Download />
      </main>

      <Footer />
    </>
  );
}
