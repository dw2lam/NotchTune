import type { ReactNode } from 'react';
import { HourglassIcon } from './icons';

/* ============================================================
   1:1 open Agents tab (IslandPanelView.swift sessionList):
   SESSIONS header (mono 10.5 tracking 1.4 @0.55, h36) +
   overview metrics, then IslandSessionRow entries.
   ============================================================ */

export type SessionState = 'running' | 'approve' | 'answer' | 'done' | 'idle';

const DOT: Record<SessionState, string> = {
  running: 'nt-dot-run nt-dot-pulse',
  approve: 'nt-dot-approve nt-dot-pulse',
  answer: 'nt-dot-answer nt-dot-pulse',
  done: 'nt-dot-done',
  idle: 'nt-dot-idle',
};

/* brand tints for agent badges */
export const AGENT_TINTS: Record<string, string> = {
  'Claude Code': '#d97757',
  Codex: '#7aa2f7',
  Gemini: '#8ab4f8',
  OpenCode: '#9ece6a',
  Kimi: '#bb9af7',
};

export interface MockSession {
  state: SessionState;
  title: string;
  branch?: string;
  prompt?: string;
  waiting?: string;       /* "Waiting 2m 14s" line (approve/answer) */
  agent: string;
  terminal?: string;
  age: string;
  command?: string;       /* running `$ cmd` box */
  subagents?: { name: string; desc: string; time: string }[];
}

export function SessionRow({ s }: { s: MockSession }) {
  const waitClass = s.state === 'approve' ? 'nt-wait-approve' : 'nt-wait-answer';
  return (
    <>
      <div className="nt-row">
        <span className={`nt-dot ${DOT[s.state]}`} />
        <div className="nt-row-main">
          <div className="nt-row-title">
            {s.title}
            {s.branch && <span className="nt-branch"> ({s.branch})</span>}
          </div>
          {s.prompt && <div className="nt-row-prompt">You: {s.prompt}</div>}
          {s.waiting && (
            <span className={`nt-row-wait ${waitClass}`}>
              <HourglassIcon /> {s.waiting}
            </span>
          )}
        </div>
        <div className="nt-row-side">
          <span className="nt-badge nt-badge-agent" style={{ '--agent': AGENT_TINTS[s.agent] ?? '#d97757' } as React.CSSProperties}>
            {s.agent}
          </span>
          {s.terminal && <span className="nt-badge nt-badge-term">{s.terminal}</span>}
          <span className="nt-age">{s.age}</span>
        </div>
      </div>
      {s.subagents?.map((sub) => (
        <div className="nt-subrow" key={sub.name}>
          <span className="nt-dot nt-dot-run" />
          <span className="nt-sub-name">{sub.name}</span>
          <span className="nt-sub-desc">{sub.desc}</span>
          <span className="nt-sub-time">{sub.time}</span>
        </div>
      ))}
      {s.command && <div className="nt-cmdbox">$ {s.command}</div>}
    </>
  );
}

export function AgentsTab({ sessions, metrics, children }: {
  sessions: MockSession[];
  metrics?: { state: SessionState; n: number }[];
  children?: ReactNode;
}) {
  return (
    <div className="nt-agents">
      <div className="nt-sess-head">
        <span className="nt-sess-title">Sessions</span>
        <span className="nt-sess-metrics">
          {(metrics ?? summarize(sessions)).map((m) => (
            <span className="nt-metric" key={m.state}>
              <span className={`nt-dot ${DOT[m.state].split(' ')[0]}`} /> {m.n}
            </span>
          ))}
        </span>
      </div>
      {sessions.map((s, i) => <SessionRow s={s} key={i} />)}
      {children}
    </div>
  );
}

function summarize(sessions: MockSession[]) {
  const counts = new Map<SessionState, number>();
  sessions.forEach((s) => counts.set(s.state, (counts.get(s.state) ?? 0) + 1));
  return [...counts.entries()].map(([state, n]) => ({ state, n }));
}
