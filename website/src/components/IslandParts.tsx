import type { ReactNode } from 'react';

/* Reusable pieces of the expanded "island" panel, matching the real app layout. */

export function UsageChip({
  name, time, pct, tone = 'u-ok',
}: { name: string; time: string; pct: string; tone?: 'u-ok' | 'u-warn' }) {
  return (
    <span className="uchip">
      <b>{name}</b>
      <em>{time}</em>
      <i className={tone}>{pct}</i>
    </span>
  );
}

const GearIcon = () => (
  <svg viewBox="0 0 24 24"><path d="M19.14 12.94a7.6 7.6 0 000-1.88l2.03-1.58a.5.5 0 00.12-.64l-1.92-3.32a.5.5 0 00-.61-.22l-2.39.96a7 7 0 00-1.62-.94l-.36-2.54a.5.5 0 00-.5-.42h-3.84a.5.5 0 00-.5.42l-.36 2.54a7 7 0 00-1.62.94l-2.39-.96a.5.5 0 00-.61.22L2.71 8.84a.5.5 0 00.12.64l2.03 1.58a7.6 7.6 0 000 1.88l-2.03 1.58a.5.5 0 00-.12.64l1.92 3.32a.5.5 0 00.61.22l2.39-.96a7 7 0 001.62.94l.36 2.54a.5.5 0 00.5.42h3.84a.5.5 0 00.5-.42l.36-2.54a7 7 0 001.62-.94l2.39.96a.5.5 0 00.61-.22l1.92-3.32a.5.5 0 00-.12-.64zM12 15.6A3.6 3.6 0 1112 8.4a3.6 3.6 0 010 7.2z" /></svg>
);
const PowerIcon = () => (
  <svg viewBox="0 0 24 24"><path d="M13 3h-2v10h2V3zm4.83 2.17-1.42 1.42A6.92 6.92 0 0119 12a7 7 0 11-14 0 6.92 6.92 0 012.59-5.41L6.17 5.17A9 9 0 1021 12a8.94 8.94 0 00-3.17-6.83z" /></svg>
);

export function IslandTop({ children }: { children: ReactNode }) {
  return (
    <div className="isl-top">
      <div className="isl-usage">{children}</div>
      <div className="isl-notch" />
      <div className="isl-tools">
        <button className="iconbtn" aria-label="Settings"><GearIcon /></button>
        <button className="iconbtn" aria-label="Quit"><PowerIcon /></button>
      </div>
    </div>
  );
}

const AgentsTabIcon = () => (
  <svg viewBox="0 0 24 24"><path d="M4 7l4 4-4 4 1.4 1.4L11 11 5.4 5.6 4 7zM12 15h6v2h-6z" /></svg>
);
const MusicTabIcon = () => (
  <svg viewBox="0 0 24 24"><path d="M12 3v10.55A4 4 0 1014 17V7h4V3h-6z" /></svg>
);

export function TabBar({ active }: { active: 'agents' | 'music' }) {
  return (
    <div className="tabbar">
      <button className={`tab${active === 'agents' ? ' is-on' : ''}`}><AgentsTabIcon />Agents</button>
      <button className={`tab${active === 'music' ? ' is-on' : ''}`}><MusicTabIcon />Music</button>
    </div>
  );
}

export function MusicView() {
  return (
    <div className="music">
      <div className="art" style={{ ['--c1' as string]: '#7b5cff', ['--c2' as string]: '#ff5c8a' }} />
      <div className="m-col">
        <div className="m-head">
          <div className="m-title">Sienna</div>
          <div className="m-artist">The Marías</div>
        </div>
        <div className="m-ctrls">
          <button className="m-ic m-side" aria-label="Shuffle"><svg viewBox="0 0 24 24"><path d="M10.59 9.17 5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z" /></svg></button>
          <button className="m-ic" aria-label="Previous"><svg viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6 8.5 6V6z" /></svg></button>
          <button className="m-ic m-big" aria-label="Pause"><svg viewBox="0 0 24 24"><path d="M6 5h4v14H6zm8 0h4v14h-4z" /></svg></button>
          <button className="m-ic" aria-label="Next"><svg viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6zM16 6v12h2V6z" /></svg></button>
          <button className="m-ic m-side" aria-label="Repeat"><svg viewBox="0 0 24 24"><path d="M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z" /></svg></button>
        </div>
        <div className="m-seek">
          <div className="m-rail"><i style={{ width: '46%' }} /></div>
          <div className="m-times"><span>1:42</span><span>3:38</span></div>
        </div>
      </div>
    </div>
  );
}
