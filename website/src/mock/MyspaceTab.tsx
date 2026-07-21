import { useState } from 'react';
import {
  Archive, ArchiveRestore, ArrowUp, AudioWaveform, Bell, BellRing, CheckCircle2,
  Circle, Clock, FileText, Film, Image as ImageIcon, Infinity as InfinityIcon,
  Inbox, Paperclip, Trash2, X,
} from 'lucide-react';

/* ============================================================
   1:1 Myspace + Reminders tabs (MyspacePanelView.swift).
   Layout: VStack(10), padding 16/―/14; list max-height 210/240.
   Rows: padding 9, r10, fill white .024, stroke white .065.
   Composer: padding 10, r12, fill white .035, stroke white .08.
   ============================================================ */

export interface MockAttachment {
  name: string;
  ext: string;
  kind?: 'image' | 'audio' | 'movie' | 'pdf' | 'doc';
  art?: string; /* css background for the 42px thumb */
}

export interface MockThought {
  text?: string;
  time: string;              /* created, h:mm:ss */
  attachments?: MockAttachment[];
  reminderAt?: string;       /* "Jul 21, 9:00 AM" — bell badge */
}

export interface MockReminder {
  text: string;
  reminderAt?: string;       /* undefined → "No time" */
  created: string;
  done?: boolean;
}

function attachmentGlyph(kind: MockAttachment['kind']) {
  switch (kind) {
    case 'image': return <ImageIcon />;
    case 'audio': return <AudioWaveform />;
    case 'movie': return <Film />;
    case 'pdf': return <FileText />;
    default: return <FileText />;
  }
}

/* Attachment preview: 48px cell (42px thumb r7, ext badge), name w66 (spec §4) */
function AttachmentPreview({ attachment }: { attachment: MockAttachment }) {
  return (
    <div className="nt-ms-att">
      <div className="nt-ms-att-cell">
        {attachment.art ? (
          <div className="nt-ms-att-thumb" style={{ background: attachment.art, backgroundSize: 'cover', backgroundPosition: 'center' }} />
        ) : (
          <div className="nt-ms-att-thumb nt-ms-att-fallback">{attachmentGlyph(attachment.kind)}</div>
        )}
        <span className="nt-ms-att-ext">{attachment.ext.toUpperCase().slice(0, 5)}</span>
      </div>
      <span className="nt-ms-att-name">{attachment.name}</span>
    </div>
  );
}

/* Day header: 9px bold mono tracking .8 white .46 + hairline (spec §3) */
export function MyspaceDayHeader({ label = 'TODAY' }: { label?: string }) {
  return (
    <div className="nt-ms-day">
      <span>{label}</span>
      <i />
    </div>
  );
}

export function ThoughtRow({ thought, onDelete }: { thought: MockThought; onDelete?: () => void }) {
  return (
    <div className="nt-ms-row">
      <div className="nt-ms-row-body">
        {thought.text && <div className="nt-ms-text">{thought.text}</div>}
        {thought.attachments && thought.attachments.length > 0 && (
          <div className="nt-ms-atts">
            {thought.attachments.map((a) => <AttachmentPreview key={a.name} attachment={a} />)}
          </div>
        )}
        <div className="nt-ms-meta">
          <Clock /> <span>{thought.time}</span>
          {thought.reminderAt && (
            <span className="nt-ms-bell"><BellRing /> {thought.reminderAt}</span>
          )}
        </div>
      </div>
      <button type="button" className="nt-ms-trash" aria-label="Delete" onClick={onDelete}><Trash2 /></button>
    </div>
  );
}

export function MyspaceTab({
  thoughts, dayLabel = 'TODAY', onSubmit, onDelete,
}: {
  thoughts: MockThought[];
  dayLabel?: string;
  onSubmit?: (text: string) => void;
  onDelete?: (index: number) => void;
}) {
  const [draft, setDraft] = useState('');

  const submit = () => {
    const text = draft.trim();
    if (!text || !onSubmit) return;
    onSubmit(text);
    setDraft('');
  };

  return (
    <div className="nt-ms">
      <div className="nt-ms-composer">
        <textarea
          className="nt-ms-input"
          placeholder="Drop a thought here…"
          value={draft}
          rows={2}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); }
          }}
        />
        <div className="nt-ms-actions">
          <button type="button" className="nt-ms-cbtn" aria-label="Attach"><Paperclip /></button>
          <span className="nt-ms-spacer" />
          <button
            type="button"
            className="nt-ms-submit"
            aria-label="Save thought"
            disabled={!draft.trim()}
            onClick={submit}
          ><ArrowUp /></button>
        </div>
      </div>

      {thoughts.length === 0 ? (
        <div className="nt-ms-empty">
          <Inbox />
          <b>Your space is quiet</b>
          <span>Save a thought or drop in a file.</span>
        </div>
      ) : (
        <div className="nt-ms-list">
          <MyspaceDayHeader label={dayLabel} />
          {thoughts.map((t, i) => (
            <ThoughtRow key={`${t.time}-${i}`} thought={t} onDelete={onDelete ? () => onDelete(i) : undefined} />
          ))}
        </div>
      )}
    </div>
  );
}

/* Reminders tab: segmented Active/Archive capsule, composer, rows (spec §B) */
export function RemindersTab({
  reminders, onToggle,
}: {
  reminders: MockReminder[];
  onToggle?: (index: number) => void;
}) {
  const [section, setSection] = useState<'active' | 'archive'>('active');
  const active = reminders.filter((r) => !r.done);
  const archived = reminders.filter((r) => r.done);
  const shown = section === 'active' ? active : archived;

  return (
    <div className="nt-ms">
      <div className="nt-rm-picker">
        <button
          type="button"
          className={`nt-rm-seg ${section === 'active' ? 'is-on' : ''}`}
          onClick={() => setSection('active')}
        ><Bell /> Active <i>{active.length}</i></button>
        <button
          type="button"
          className={`nt-rm-seg ${section === 'archive' ? 'is-on' : ''}`}
          onClick={() => setSection('archive')}
        ><Archive /> Archive <i>{archived.length}</i></button>
      </div>

      {shown.length === 0 ? (
        <div className="nt-ms-empty">
          {section === 'active' ? <BellRing /> : <ArchiveRestore />}
          <b>{section === 'active' ? 'No active reminders' : 'Archive is empty'}</b>
          <span>
            {section === 'active'
              ? 'Keep a reminder here, or add a time when it should notify you.'
              : 'Completed reminders will live here.'}
          </span>
        </div>
      ) : (
        <div className="nt-ms-list">
          {shown.map((r) => {
            const index = reminders.indexOf(r);
            return (
              <div className="nt-ms-row" key={r.text}>
                <button
                  type="button"
                  className={`nt-rm-toggle ${r.done ? 'is-done' : ''}`}
                  aria-label={r.done ? 'Completed' : 'Complete'}
                  onClick={onToggle ? () => onToggle(index) : undefined}
                >{r.done ? <CheckCircle2 /> : <Circle />}</button>
                <div className="nt-ms-row-body">
                  <div className={`nt-ms-text ${r.done ? 'nt-rm-done' : ''}`}>{r.text}</div>
                  <div className="nt-ms-meta">
                    {r.reminderAt
                      ? <><BellRing /> <span>{r.reminderAt}</span></>
                      : <><InfinityIcon /> <span>No time</span></>}
                    <span className="nt-ms-dot">·</span>
                    <Clock /> <span>{r.created}</span>
                  </div>
                </div>
                <button type="button" className="nt-ms-trash" aria-label="Delete"><Trash2 /></button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

/* The "Throw anything in" drop target (IslandPanelView fileDragTargetContent):
   tray icon 23 light white .46 · 12.5 semibold white .68 · 9.5 medium white .3,
   dashed r14 stroke white .13 [6,5] inset 7, fill white .018. */
export function MyspaceDropTarget() {
  return (
    <div className="nt-ms-drop">
      <Inbox className="nt-ms-drop-icon" />
      <b>Throw anything in</b>
      <span>Release to hold a copy in Myspace</span>
    </div>
  );
}
