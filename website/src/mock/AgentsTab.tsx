import type { ReactNode } from 'react';
import { HourglassIcon, ChevronIcon, CheckIcon } from './icons';

/* ============================================================
   1:1 open Agents tab (IslandPanelView.swift sessionList):
   SESSIONS header (mono 10.5 tracking 1.4 @0.55, h36) with
   labeled overview metrics ("4 total • 2 running • 2 done"),
   then IslandSessionRow entries — glyph state indicators
   (running ring / done check / waiting pulse), lowercase agent
   badge, terminal badge, age, collapse chevron.
   ============================================================ */

export type SessionState = 'running' | 'approve' | 'answer' | 'done' | 'idle';

/* brand tints for agent badges (badge text is the lowercase agent name) */
export const AGENT_TINTS: Record<string, string> = {
  claude: '#d97757',
  codex: '#7aa2f7',
  gemini: '#8ab4f8',
  opencode: '#9ece6a',
  kimi: '#bb9af7',
};

export function StateIndicator({ state }: { state: SessionState }) {
  switch (state) {
    case 'running':
      return <span className="nt-ind nt-ind-run" />;
    case 'done':
      return <span className="nt-ind nt-ind-done"><CheckIcon /></span>;
    case 'idle':
      return <span className="nt-dot nt-dot-idle nt-ind-dot" />;
    case 'approve':
      return <span className="nt-dot nt-dot-approve nt-dot-pulse nt-ind-dot" />;
    case 'answer':
      return <span className="nt-dot nt-dot-answer nt-dot-pulse nt-ind-dot" />;
  }
}

export interface MockSession {
  state: SessionState;
  title: string;
  branch?: string;
  prompt?: string;
  waiting?: string;       /* "Waiting 2m 14s" line (approve/answer) */
  agent: string;          /* lowercase agent name, e.g. "claude" */
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
        <StateIndicator state={s.state} />
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
          <button type="button" className="nt-chev" aria-label="Toggle details"><ChevronIcon /></button>
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

const METRIC_LABEL: Partial<Record<SessionState, string>> = {
  running: 'running',
  approve: 'waiting',
  answer: 'waiting',
  done: 'done',
  idle: 'idle',
};
const METRIC_DOT: Partial<Record<SessionState, string>> = {
  running: 'nt-dot-run',
  approve: 'nt-dot-approve',
  answer: 'nt-dot-answer',
  done: 'nt-dot-done',
  idle: 'nt-dot-idle',
};

export function AgentsTab({ sessions, children }: {
  sessions: MockSession[];
  children?: ReactNode;
}) {
  const counts = new Map<string, { dot: string; n: number }>();
  sessions.forEach((s) => {
    const label = METRIC_LABEL[s.state]!;
    const prev = counts.get(label);
    counts.set(label, { dot: METRIC_DOT[s.state]!, n: (prev?.n ?? 0) + 1 });
  });
  return (
    <div className="nt-agents">
      <div className="nt-sess-head">
        <span className="nt-sess-title">Sessions</span>
        <span className="nt-sess-metrics">
          <span className="nt-metric">{sessions.length} total</span>
          {[...counts.entries()].map(([label, { dot, n }]) => (
            <span className="nt-metric" key={label}>
              <span className={`nt-dot ${dot}`} /> {n} {label}
            </span>
          ))}
        </span>
      </div>
      {sessions.map((s, i) => <SessionRow s={s} key={i} />)}
      {children}
    </div>
  );
}
