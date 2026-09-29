import { useState, type CSSProperties, type ReactNode } from 'react';
import { AGENT_TINTS, AGENT_NAMES } from './AgentsTab';
import { ChevronIcon, CheckIcon, JumpIcon, ReplyIcon, ChevronLeftIcon, ChevronRightIcon } from './icons';

/* ============================================================
   Notification surfaces (opened with reason .notification — no
   tab bar, the card starts right under the notch):
   - NotificationSessionHeader: IslandSessionRow.notificationRowSummary
   - ApprovalCard: approvalActionBody — glass Deny / Allow capsules
     with ⌘N / ⌘Y key hints (NotificationKeyHint 9pt @0.4)
   - QuestionCard: StructuredQuestionPromptView — numbered options
     picked with ⌘1–9, ⏎ submits
   - CompletionToast: CompletionToastView — ≤20% of screen height,
     3-line plain excerpt, Jump / Reply / All N sessions
   ============================================================ */

export function KeyHint({ keys }: { keys: string }) {
  return <span className="nt-khint" aria-hidden="true">{keys}</span>;
}

/** Title + "You:" line + lowercase agent badge, terminal, age, chevron. */
export function NotificationSessionHeader({ title, prompt, agent, terminal, age }: {
  title: string; prompt?: string; agent: string; terminal?: string; age: string;
}) {
  return (
    <div className="nt-nrow">
      <div className="nt-nrow-main">
        <div className="nt-nrow-title">{title}</div>
        {prompt && <div className="nt-nrow-prompt">You: {prompt}</div>}
      </div>
      <div className="nt-nrow-side">
        <span className="nt-badge nt-badge-agent" style={{ '--agent': AGENT_TINTS[agent] ?? '#d97742' } as CSSProperties}>
          {agent}
        </span>
        {terminal && <span className="nt-badge nt-badge-term">{terminal}</span>}
        <span className="nt-age">{age}</span>
        <span className="nt-gdisc nt-chev" aria-hidden="true"><ChevronIcon /></span>
      </div>
    </div>
  );
}

export function ShowAll({ count, onClick }: { count: number; onClick?: () => void }) {
  return (
    <button type="button" className="nt-showall" onClick={onClick}>Show all {count} sessions</button>
  );
}

/* approvalActionBody: "Tool permission requested" 12.5/600 paper@0.86 ·
   command well RR10 white@0.045 pad 12/8 (mono 11.5/600 @0.78 + path
   10.5/500 @0.42) · [Deny ⌘N glass][Allow ⌘Y warm glass] expanding. */
export function ApprovalCard({
  command, path, alwaysTool, onDeny, onAllow, onAlwaysAllow,
}: {
  command: string;
  path?: string;
  /** when set, shows the third "Always allow <tool>" ⇧⌘Y button */
  alwaysTool?: string;
  onDeny?: () => void;
  onAllow?: () => void;
  onAlwaysAllow?: () => void;
}) {
  return (
    <div className="nt-notify">
      <div className="nt-notify-title">Tool permission requested</div>
      <div className="nt-notify-well">
        <div className="nt-notify-cmd">$ {command}</div>
        {path && <div className="nt-notify-path">{path}</div>}
      </div>
      <div className="nt-actions">
        <button type="button" className="nt-gbtn nt-gbtn-secondary" onClick={onDeny}>Deny <KeyHint keys="⌘N" /></button>
        <button type="button" className="nt-gbtn nt-gbtn-warning" onClick={onAllow}>Allow <KeyHint keys="⌘Y" /></button>
        {alwaysTool && (
          <button type="button" className="nt-gbtn nt-gbtn-primary" onClick={onAlwaysAllow}>
            Always allow {alwaysTool} <KeyHint keys="⇧⌘Y" />
          </button>
        )}
      </div>
    </div>
  );
}

export interface MockOption { label: string; desc?: string }

export function QuestionCard({ question, options, onSubmit }: {
  question: string;
  options: MockOption[];
  onSubmit?: (label: string) => void;
}) {
  const [picked, setPicked] = useState<number | null>(null);
  return (
    <div className="nt-notify">
      <div className="nt-qcard">
        <div className="nt-q-text">{question}</div>
        <div className="nt-q-opts">
          {options.map((o, i) => (
            <button
              type="button" key={o.label}
              className={`nt-q-opt ${picked === i ? 'is-on' : ''}`}
              onClick={() => setPicked(i)}
              title={`⌘${i + 1}`}
            >
              <span className="nt-q-key">{i + 1}</span>
              <span className="nt-q-label">
                <b>{o.label}</b>
                {o.desc && <em>{o.desc}</em>}
              </span>
              {picked === i && <span className="nt-q-check"><CheckIcon /></span>}
            </button>
          ))}
        </div>
        <button
          type="button"
          className={`nt-gbtn nt-gbtn-wide ${picked === null ? 'nt-gbtn-disabled' : 'nt-gbtn-primary'}`}
          disabled={picked === null}
          onClick={() => picked !== null && onSubmit?.(options[picked].label)}
        >
          Submit Answers {picked !== null && <KeyHint keys="⏎" />}
        </button>
      </div>
    </div>
  );
}

/* CompletionToastView: header (7pt green dot, "<Agent> finished"
   12.5/600, workspace 11.5/500 @0.55, terminal + age mono 10.5 @0.42) ·
   "You:" 11/500 @0.5 · excerpt 12.5 regular @0.88, 3 lines ·
   [Jump to <terminal> ⏎][Reply] … [‹ 1/2 ›] All N sessions */
export function CompletionToast({
  agent, workspace, terminal = 'Ghostty', age = '<1m', prompt, excerpt,
  total = 9, queue, onJump, onReply, onShowAll, onRotate, extra,
}: {
  agent: string;
  workspace: string;
  terminal?: string;
  age?: string;
  prompt?: string;
  excerpt: string;
  total?: number;
  queue?: { index: number; count: number };
  onJump?: () => void;
  onReply?: () => void;
  onShowAll?: () => void;
  onRotate?: (forward: boolean) => void;
  extra?: ReactNode;
}) {
  return (
    <div className="nt-toast">
      <div className="nt-toast-head">
        <span className="nt-toast-dot" />
        <b>{AGENT_NAMES[agent] ?? agent} finished</b>
        <span className="nt-toast-ws">{workspace}</span>
        <span className="nt-toast-meta">{terminal} {age}</span>
      </div>
      {prompt && <div className="nt-toast-prompt">You: {prompt}</div>}
      <p className="nt-toast-excerpt">{excerpt}</p>
      {extra}
      <div className="nt-toast-actions">
        <button type="button" className="nt-gbtn nt-gbtn-sm nt-gbtn-primary" onClick={onJump}>
          <JumpIcon /> Jump to {terminal} <KeyHint keys="⏎" />
        </button>
        <button type="button" className="nt-gbtn nt-gbtn-sm nt-gbtn-secondary" onClick={onReply}>
          <ReplyIcon /> Reply
        </button>
        <span className="nt-toast-spacer" />
        {queue && queue.count > 1 && (
          <span className="nt-toast-queue">
            <button type="button" className="nt-gdisc nt-gdisc-sm" aria-label="Previous" onClick={() => onRotate?.(false)}><ChevronLeftIcon /></button>
            <span>{queue.index + 1}/{queue.count}</span>
            <button type="button" className="nt-gdisc nt-gdisc-sm" aria-label="Next" onClick={() => onRotate?.(true)}><ChevronRightIcon /></button>
          </span>
        )}
        <button type="button" className="nt-toast-all" onClick={onShowAll}>All {total} sessions</button>
      </div>
    </div>
  );
}
