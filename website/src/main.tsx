import { createRoot } from 'react-dom/client';
import './site.css';
import App from './App';

// Reveal-on-scroll only hides content once script is running.
document.documentElement.classList.add('js');

createRoot(document.getElementById('root')!).render(<App />);
