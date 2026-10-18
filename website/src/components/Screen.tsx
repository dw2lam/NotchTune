import type { ReactNode } from 'react';

/* The top of a Mac display: wallpaper, menu bar, and whatever hangs from the
   notch (a closed pill or the opened island). */
export function Screen({
  height, wallpaper = '/assets/wallpapers/sky.jpg', app = 'Ghostty', slice = false, minimal = false, children,
}: {
  height?: number;
  wallpaper?: string;
  app?: string;
  /** just the menu-bar strip, for closed-pill shots */
  slice?: boolean;
  /** only the Apple menu, so a wide pill has room */
  minimal?: boolean;
  children?: ReactNode;
}) {
  return (
    <div
      className={`screen${slice ? ' is-slice' : ''}`}
      style={{ height, ['--wall' as string]: `url(${wallpaper})` }}
    >
      <div className="screen-menubar">
        <span>
          <AppleGlyph />
          {!minimal && <><b>{app}</b><span>File</span><span>Edit</span><span>View</span></>}
        </span>
        <span>
          <WifiGlyph />
          <BatteryGlyph />
          <span>Tue 9:41</span>
        </span>
      </div>
      <div className="screen-notch">{children}</div>
    </div>
  );
}

function AppleGlyph() {
  return (
    <svg viewBox="0 0 16 16"><path d="M11.2 8.5c0-1.5 1.2-2.2 1.3-2.3-.7-1-1.8-1.2-2.2-1.2-.9-.1-1.8.6-2.3.6-.5 0-1.2-.5-2-.5-1 0-2 .6-2.5 1.6-1.1 1.9-.3 4.6.8 6.1.5.7 1.1 1.6 1.9 1.5.8 0 1-.5 2-.5s1.2.5 2 .5 1.3-.8 1.8-1.5c.6-.8.8-1.6.8-1.7 0 0-1.6-.6-1.6-2.6ZM9.7 4.1c.4-.5.7-1.2.6-1.9-.6 0-1.4.4-1.8.9-.4.4-.7 1.1-.6 1.8.7.1 1.4-.3 1.8-.8Z" /></svg>
  );
}
function WifiGlyph() {
  return (
    <svg viewBox="0 0 16 16"><path d="M8 12.6a1.2 1.2 0 1 1 0 2.4 1.2 1.2 0 0 1 0-2.4ZM8 9c1.3 0 2.5.5 3.4 1.4l-1 1A3.4 3.4 0 0 0 8 10.4c-.9 0-1.8.4-2.4 1l-1-1C5.5 9.5 6.7 9 8 9Zm0-3.6c2.3 0 4.4.9 6 2.5l-1 1A7 7 0 0 0 8 6.8 7 7 0 0 0 3 8.9l-1-1C3.6 6.3 5.7 5.4 8 5.4Z" /></svg>
  );
}
function BatteryGlyph() {
  return (
    <svg viewBox="0 0 22 16"><path d="M3 4h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Zm0 1.2a.8.8 0 0 0-.8.8v4c0 .4.4.8.8.8h14c.4 0 .8-.4.8-.8V6a.8.8 0 0 0-.8-.8Zm.8 1h10.4v3.6H3.8ZM20 6.6c.6.2 1 .8 1 1.4s-.4 1.2-1 1.4Z" /></svg>
  );
}
