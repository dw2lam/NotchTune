import { createRoot } from 'react-dom/client';
import './site.css';
import App from './App';

// Reveal-on-scroll only hides content once script is running.
document.documentElement.classList.add('js');
// A deep link lands mid-story, where the lid has no business still opening.
if (location.hash.length > 1 && location.hash !== '#top') document.documentElement.classList.add('linked');

createRoot(document.getElementById('root')!).render(<App />);
