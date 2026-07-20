/* ============================================================
   1:1 approval notification body (IslandPanelView.swift:2097-2145):
   "tool permission requested" 12.5/600 paper@0.86 · `$ cmd` box
   mono 11.5/600 paper@0.78 RR7 white@0.045 · path 10.5/500 @0.42 ·
   [Deny secondary][Allow Once warning][Always allow primary].
   ============================================================ */

export function ApprovalCard({
  agent = 'Claude Code', tool = 'Bash', command, path,
  onDeny, onAllowOnce, onAlwaysAllow,
}: {
  agent?: string;
  tool?: string;
  command: string;
  path?: string;
  onDeny?: () => void;
  onAllowOnce?: () => void;
  onAlwaysAllow?: () => void;
}) {
  return (
    <div className="nt-notify">
      <div className="nt-notify-head">
        <span className="nt-dot nt-dot-approve nt-dot-pulse" style={{ width: 9, height: 9 }} />
        <span className="nt-notify-title">{agent} — tool permission requested</span>
      </div>
      <div className="nt-notify-cmd">$ {command}</div>
      {path && <div className="nt-notify-path">{path}</div>}
      <div className="nt-actions">
        <button type="button" className="nt-abtn nt-abtn-secondary" onClick={onDeny}>Deny</button>
        <button type="button" className="nt-abtn nt-abtn-warning" onClick={onAllowOnce}>Allow Once</button>
        <button type="button" className="nt-abtn nt-abtn-primary" onClick={onAlwaysAllow}>Always allow {tool}</button>
      </div>
    </div>
  );
}
