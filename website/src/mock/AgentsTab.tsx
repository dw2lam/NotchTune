import type { CSSProperties, ReactNode } from 'react';
import { HourglassIcon, CheckIcon } from './icons';

/* ============================================================
   1:1 open Agents tab (IslandPanelView.swift):
   - counts line (sessionPanelHeader): "9 total" paper@0.34, then
     5.5pt tinted dot + "1 running" 11/medium paper@0.48, gap 9, h24
   - rows (IslandSessionRow.listRowSummary): state indicator centred
     on the block (20pt column, gap 12), 13.5 semibold title, flat
     pills on the title line — agent tag in brand colour on a 16%
     tint, terminal + age pills white@0.08 — RR5, pad 7/3, 11pt.
     No dividers, no chevrons: the whole row jumps to the terminal.
   - subtitle (listSubtitleLines, 12/medium): running rows show
     "You: <prompt>" then the activity phrase with the verb in the
     running blue; other rows show one plain line at paper@0.5.
   ============================================================ */

export type SessionState = 'running' | 'approve' | 'answer' | 'done' | 'idle';

/* AgentTool.brandColorHex (NotchTuneCore/AgentSession.swift:83) */
export const AGENT_TINTS: Record<string, string> = {
  claude: '#d97742',
  codex: '#4aa3df',
  gemini: '#42e86b',
  opencode: '#ffb547',
  qwen: '#c084fc',
  kimi: '#fde047',
  cursor: '#7a5cff',
  factory: '#6e9fff',
};

/* completionReplyRecipientName — the tag reads "Claude", "Codex"… */
export const AGENT_NAMES: Record<string, string> = {
  claude: 'Claude',
  codex: 'Codex',
  gemini: 'Gemini',
  opencode: 'OpenCode',
  qwen: 'Qwen',
  kimi: 'Kimi',
  cursor: 'Cursor',
  factory: 'Droid',
};

export type IndicatorStyle = 'dot' | 'glyph';

export function StateIndicator({ state, style = 'dot' }: { state: SessionState; style?: IndicatorStyle }) {
  if (style === 'glyph') {
    /* SF glyphs: circle.dashed · checkmark.circle.fill ·
       exclamationmark.triangle.fill · questionmark.circle.fill */
    switch (state) {
      case 'running':
        return <span className="nt-ind nt-ind-run" />;
      case 'done':
      case 'idle':
        return <span className={`nt-ind nt-ind-done ${state === 'idle' ? 'is-idle' : ''}`}><CheckIcon /></span>;
      case 'approve':
        return <span className="nt-ind nt-ind-glyph nt-wait-approve">!</span>;
      case 'answer':
        return <span className="nt-ind nt-ind-glyph nt-wait-answer is-q">?</span>;
    }
  }
  /* animatedDot (app default): 9pt dot, 1.96s sine pulse while live,
     top-padded 6 inside a 10×24 frame */
  const live = state === 'running' || state === 'approve' || state === 'answer';
  return (
    <span className="nt-ind-frame">
      <span className={`nt-dot nt-dot-${state === 'approve' ? 'approve' : state === 'answer' ? 'answer' : state === 'running' ? 'run' : state === 'done' ? 'done' : 'idle'} nt-ind-dot ${live ? 'nt-dot-pulse' : ''}`} />
    </span>
  );
}

export interface MockSession {
  state: SessionState;
  /** headline, e.g. "api · Make BridgeServer dispatch…" */
  title: string;
  prompt?: string;        /* running rows: "You: …" */
  activity?: string;      /* running rows: "Running swift test" (first word tinted) */
  summary?: string;       /* done rows: first line of the last reply */
  waiting?: string;       /* "Waiting 2m 14s" line (approve/answer) */
  agent: string;          /* key into AGENT_TINTS, e.g. "claude" */
  terminal?: string;
  age: string;
}

function ActivityLine({ text }: { text: string }) {
  const i = text.indexOf(' ');
  if (i < 0) return <span className="nt-verb">{text}</span>;
  return <><span className="nt-verb">{text.slice(0, i)}</span>{text.slice(i)}</>;
}

export function AgentTag({ agent }: { agent: string }) {
  return (
    <span className="nt-lpill nt-lpill-agent" style={{ '--agent': AGENT_TINTS[agent] ?? '#f1ead9' } as CSSProperties}>
      {AGENT_NAMES[agent] ?? agent}
    </span>
  );
}

export function SessionRow({ s, indicator = 'dot' }: { s: MockSession; indicator?: IndicatorStyle }) {
  const inactive = s.state === 'idle';
  return (
    <div className={`nt-row ${inactive ? 'is-inactive' : ''}`}>
      <StateIndicator state={s.state} style={indicator} />
      <div className="nt-row-main">
        <div className="nt-row-line">
          <span className="nt-row-title">{s.title}</span>
          <span className="nt-row-pills">
            <AgentTag agent={s.agent} />
            {s.terminal && <span className="nt-lpill">{s.terminal}</span>}
            <span className="nt-lpill nt-lpill-age">{s.age}</span>
          </span>
        </div>
        {s.state === 'running' && s.prompt && (
          <div className="nt-row-sub nt-row-prompt"><span>You: </span>{s.prompt}</div>
        )}
        {s.state === 'running' && s.activity && (
          <div className="nt-row-sub"><ActivityLine text={s.activity} /></div>
        )}
        {s.state !== 'running' && !inactive && s.summary && (
          <div className="nt-row-sub">{s.summary}</div>
        )}
        {s.waiting && (
          <span className={`nt-row-wait ${s.state === 'approve' ? 'nt-wait-approve' : 'nt-wait-answer'}`}>
            <HourglassIcon /> {s.waiting}
          </span>
        )}
      </div>
    </div>
  );
}

const METRICS: { id: string; label: string; dot?: string; match: (s: SessionState) => boolean }[] = [
  { id: 'waiting', label: 'waiting', dot: 'nt-dot-agg', match: (s) => s === 'approve' || s === 'answer' },
  { id: 'running', label: 'running', dot: 'nt-dot-run', match: (s) => s === 'running' },
  { id: 'done', label: 'done', dot: 'nt-dot-done', match: (s) => s === 'done' },
  { id: 'idle', label: 'idle', dot: 'nt-dot-idle', match: (s) => s === 'idle' },
];

/** "9 total • 1 running • 1 done" — counts line above the rows */
export function SessionCounts({ sessions, total }: { sessions: MockSession[]; total?: number }) {
  return (
    <div className="nt-counts">
      <span className="nt-metric nt-metric-total">{total ?? sessions.length} total</span>
      {METRICS.map((m) => {
        const n = sessions.filter((s) => m.match(s.state)).length;
        if (!n) return null;
        return (
          <span className="nt-metric" key={m.id}>
            <span className={`nt-dot ${m.dot}`} /> {n} {m.label}
          </span>
        );
      })}
    </div>
  );
}

export function AgentsTab({ sessions, total, indicator = 'dot', children }: {
  sessions: MockSession[];
  /** overrides the "N total" count (rows below may be a subset) */
  total?: number;
  indicator?: IndicatorStyle;
  children?: ReactNode;
}) {
  return (
    <div className="nt-agents">
      <SessionCounts sessions={sessions} total={total} />
      {sessions.map((s, i) => <SessionRow s={s} key={i} indicator={indicator} />)}
      {children}
    </div>
  );
}
