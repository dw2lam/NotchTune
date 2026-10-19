import { useEffect, useRef, useState, type CSSProperties } from 'react';
import { useLatestRelease } from '../hooks/useLatestRelease';
import MacBook from '../components/MacBook';

/* The page's one big moment: a MacBook that opens as you arrive, then, as
   you scroll, moves in on the notch and steps through what NotchTune shows
   there. Every picture on the screen is a real capture of the app (made by
   its headless harness at 2x), placed at its true size in macOS points. */

type LayerId = 'pill-working' | 'island' | 'pill-waiting' | 'summary' | 'player' | 'myspace' | 'reminders' | 'pill-meeting' | 'banner' | 'settings';

// w/h in points; `top` is where the image sits on the screen (the island
// hangs from the very top, the Settings window sits under the menu bar).
// The closed pills' wings are uneven, so `dx` puts their notch gap on the
// notch: how far the image's centre sits from the screen's.
const LAYERS: { id: LayerId; src: string; w: number; h: number; top?: number; dx?: number; alt: string }[] = [
  { id: 'pill-working', src: 'pill-working', w: 468, h: 38, dx: -54, alt: 'The closed notch while Claude Code works in api: running swift test, 41 seconds in.' },
  { id: 'island', src: 'island', w: 650, h: 354, alt: 'The island open under the notch: usage limits, then four sessions. Claude is running swift test in api, Codex fixed the checkout button in web, Claude wrote the release notes in docs, and Codex renamed the color tokens in design-system.' },
  { id: 'pill-waiting', src: 'pill-waiting', w: 488, h: 38, dx: -64, alt: 'The closed notch turned amber: Codex needs approval to run git push origin main, waiting 13 seconds.' },
  { id: 'summary', src: 'completion', w: 550, h: 203, alt: 'The island showing a finished task: Claude Code finished in web. Edited 4 files, tests passed, 3 minutes 12 seconds, with Jump to Ghostty and Reply.' },
  { id: 'player', src: 'music', w: 650, h: 283, alt: 'The island on its Music tab: Still Water by Juniper Coast at 1:21 of 3:56, with shuffle, previous, pause, next and repeat.' },
  { id: 'myspace', src: 'myspace', w: 650, h: 430, alt: 'The island on its Myspace tab: a box to drop a thought, filters for text, images and files, today\'s three images, and a note about lazy-loading the product grid.' },
  { id: 'reminders', src: 'reminders', w: 650, h: 374, alt: 'The island on its Reminders tab: three active reminders, from checking the staging deploy at 10:00 to booking the onboarding design review, and one in the archive.' },
  { id: 'pill-meeting', src: 'pill-meeting', w: 464, h: 38, dx: -29, alt: 'The closed notch four minutes before Design review, 09:53 to 10:23.' },
  { id: 'banner', src: 'meeting', w: 650, h: 416, alt: 'The island with the Design review banner above the agent list: in 4 minutes, 09:54 to 10:24, with Join.' },
  { id: 'settings', src: 'settings-window', w: 906, h: 766, top: 52, alt: 'NotchTune Settings on Personalization: previews of the MacBook notch and an external display linked with Sync, and the first row of twenty pixel characters.' },
];

type CamId = 'full' | 'notch' | 'pill' | 'window';

const FRAMES: { id?: string; cam: CamId; layer: LayerId; title?: string; line?: string }[] = [
  { cam: 'full', layer: 'island' },
  {
    id: 'agents', cam: 'notch', layer: 'island',
    title: 'All your agents, at a glance.',
    line: 'Claude Code, Codex, Gemini CLI and six more, one line each: what it’s doing, in which terminal, and for how long.',
  },
  {
    cam: 'pill', layer: 'pill-working',
    title: 'Watch them work.',
    line: 'With the notch closed, it still says what’s running and for how long.',
  },
  {
    cam: 'pill', layer: 'pill-waiting',
    title: 'Amber when one needs you.',
    line: 'Allow with ⌘Y or deny with ⌘N, and the agent carries on.',
  },
  {
    id: 'summaries', cam: 'notch', layer: 'summary',
    title: 'Every finished task, in one line.',
    line: 'Files edited, whether the tests passed, and how long it took. Return jumps back to the terminal.',
  },
  {
    id: 'music', cam: 'notch', layer: 'player',
    title: 'Music without switching apps.',
    line: 'Spotify or Apple Music under the notch: the cover, the controls, and a two-finger swipe to skip.',
  },
  {
    id: 'myspace', cam: 'notch', layer: 'myspace',
    title: 'A space for loose thoughts.',
    line: 'Jot a note or drop a file on the notch. Images, screenshots and files wait for you there, on your Mac.',
  },
  {
    cam: 'notch', layer: 'reminders',
    title: 'Reminders, right up top.',
    line: 'Add one with or without a time, get a nudge when it’s due, and tick it off into the archive.',
  },
  {
    id: 'meetings', cam: 'notch', layer: 'banner',
    title: 'Meetings, a few minutes early.',
    line: 'A countdown, then a Join button, then quiet while you’re in the call. Your calendars never leave your Mac.',
  },
  {
    id: 'personalize', cam: 'window', layer: 'settings',
    title: 'Make it yours.',
    line: 'Twenty characters and how lively they are. Style the notch and an external display apart, or Sync both.',
  },
];

const LAST = FRAMES.length - 1;
const HOLD = 0.6; // frames of scroll the last step stays pinned for
const SPAN = 0.72; // viewport heights of scroll per step

type Cam = { z: number; x: number; y: number };

const clamp = (v: number, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export default function Story() {
  const { downloadUrl } = useLatestRelease();
  const storyRef = useRef<HTMLElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const introRef = useRef<HTMLDivElement>(null);
  const camRef = useRef<HTMLDivElement>(null);
  const shadeRef = useRef<HTMLDivElement>(null);
  const captionsRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);
  const [boot, setBoot] = useState(0); // 0 screen off, 1 Claude working, 2 island open
  const [meetingOpen, setMeetingOpen] = useState(false);

  // arrival: the lid opens, the screen wakes, Claude works, the island opens
  useEffect(() => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) { setBoot(2); return; }
    const a = setTimeout(() => setBoot(1), 2000);
    const b = setTimeout(() => setBoot(2), 3200);
    return () => { clearTimeout(a); clearTimeout(b); };
  }, []);

  // the meeting pill opens into its banner after a beat
  const meetingStep = FRAMES.findIndex((f) => f.id === 'meetings');
  useEffect(() => {
    setMeetingOpen(false);
    if (active !== meetingStep) return;
    const t = setTimeout(() => setMeetingOpen(true), 1300);
    return () => clearTimeout(t);
  }, [active, meetingStep]);

  // the camera follows the scroll; React only hears about step changes
  useEffect(() => {
    const story = storyRef.current!, stage = stageRef.current!, cam = camRef.current!;
    const intro = introRef.current!, shade = shadeRef.current!, captions = captionsRef.current!;
    const reduce = matchMedia('(prefers-reduced-motion: reduce)');
    let cams: Record<CamId, Cam> = { full: { z: 1, x: 0, y: 0 }, notch: { z: 1, x: 0, y: 0 }, pill: { z: 1, x: 0, y: 0 }, window: { z: 1, x: 0, y: 0 } };
    let span = 1, current = -1, raf = 0;

    const measure = () => {
      const screen = cam.querySelector<HTMLElement>('.mbp-screen')!;
      const lid = screen.offsetParent as HTMLElement, mbp = lid.offsetParent as HTMLElement;
      const sx = screen.offsetLeft + lid.offsetLeft + mbp.offsetLeft;
      const sy = screen.offsetTop + lid.offsetTop + mbp.offsetTop;
      const pt = screen.offsetWidth / 1512;
      const vw = stage.clientWidth, vh = stage.clientHeight;
      const css = getComputedStyle(stage);
      const nav = parseFloat(css.getPropertyValue('--nav-h')) || 48;
      const pad = parseFloat(getComputedStyle(intro).paddingLeft) || 20;
      const room = Math.max(...[...captions.children].map((c) => (c as HTMLElement).offsetHeight)) + pad * 2 + 16;
      const top = nav + Math.max(20, vh * 0.045);
      // focus point (in points on the screen) to a place on the stage, at P css px per point
      const aim = (fx: number, fy: number, P: number): Cam => {
        const z = P / pt;
        return { z, x: vw / 2 - cam.offsetLeft - (sx + fx * pt) * z, y: top - cam.offsetTop - (sy + fy * pt) * z };
      };
      const wide = Math.min(1, (vw - pad * 2) / 680, (vh - top - room) / 440);
      cams = {
        full: { z: 1, x: 0, y: 0 },
        notch: aim(756, 0, wide),
        pill: aim(756, 0, Math.min(1.2, wide * 1.18)),
        window: aim(756, 0, Math.min(1, (vw - pad * 2) / 880, (vh - top - room) / 826)),
      };
      span = (story.offsetHeight - stage.offsetHeight) / (LAST + HOLD);
    };

    const update = () => {
      raf = 0;
      const s = clamp(-story.getBoundingClientRect().top / span, 0, LAST + HOLD);
      const i = Math.min(Math.floor(s), LAST);
      const next = Math.min(i + 1, LAST);
      let t = i === LAST ? 0 : clamp((s - i - 0.15) / 0.7);
      t = reduce.matches ? (t < 0.5 ? 0 : 1) : ease(t);
      const a = cams[FRAMES[i].cam], b = cams[FRAMES[next].cam];
      const z = a.z + (b.z - a.z) * t, x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t;
      cam.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${z})`;
      const away = clamp(s / 0.45);
      intro.style.opacity = String(1 - away);
      intro.style.transform = `translateY(${-24 * away}px)`;
      intro.style.visibility = away >= 1 ? 'hidden' : '';
      shade.style.opacity = String(clamp(s / 0.6));
      const step = Math.min(LAST, Math.round(s));
      if (step !== current) { current = step; setActive(step); }
    };
    const queue = () => { if (!raf) raf = requestAnimationFrame(update); };
    const relayout = () => { measure(); update(); };

    relayout();
    const ro = new ResizeObserver(relayout);
    ro.observe(stage); ro.observe(story);
    addEventListener('scroll', queue, { passive: true });
    reduce.addEventListener('change', queue);
    return () => {
      ro.disconnect();
      removeEventListener('scroll', queue);
      reduce.removeEventListener('change', queue);
      cancelAnimationFrame(raf);
    };
  }, []);

  let shown: LayerId | null = FRAMES[active].layer;
  if (active === 0) shown = boot === 0 ? null : boot === 1 ? 'pill-working' : 'island';
  if (active === meetingStep && !meetingOpen) shown = 'pill-meeting';

  return (
    <section ref={storyRef} className="story" style={{ height: `calc(100svh + ${(LAST + HOLD) * SPAN * 100}svh)` }} aria-labelledby="hero-title">
      {FRAMES.map((f, i) => f.id && (
        <span key={f.id} id={f.id} className="story-anchor" style={{ top: `calc(${(i - 0.02) * SPAN * 100}svh)` }} />
      ))}
      <div ref={stageRef} className="story-stage">
        <div ref={introRef} className="story-intro frame">
          <h1 id="hero-title" className="h1">The calm at the top of your screen.</h1>
          <p className="cta">
            <a className="btn" href={downloadUrl}>Download for Mac</a>
            <a className="more" href="https://github.com/dw2lam/NotchTune">View on GitHub</a>
          </p>
        </div>
        <div ref={camRef} className="story-cam">
          <MacBook label="A MacBook Pro with NotchTune under the notch.">
            {LAYERS.map((l) => (
              <img
                key={l.id}
                className={`layer layer-${l.id}${shown === l.id ? ' on' : ''}`}
                src={`/assets/shots/${l.src}.webp`}
                width={l.w}
                height={l.h}
                alt={shown === l.id ? l.alt : ''}
                aria-hidden={shown === l.id ? undefined : true}
                style={{ '--w': l.w, '--h': l.h, '--top': l.top ?? 0, '--dx': l.dx ?? 0 } as CSSProperties}
                decoding="async"
                {...(l.id === 'island' || l.id === 'pill-working' ? { fetchPriority: 'high' as const } : {})}
              />
            ))}
          </MacBook>
        </div>
        <div ref={shadeRef} className={`story-shade${FRAMES[active].cam === 'window' ? ' short' : ''}`} />
        <div ref={captionsRef} className="story-captions frame" aria-live="polite">
          {FRAMES.map((f, i) => f.title && (
            <div key={i} className={`caption${active === i ? ' on' : ''}`} aria-hidden={active === i ? undefined : true}>
              <h2 className="h2">{f.title}</h2>
              <p className="lede">{f.line}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
