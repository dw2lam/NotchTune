import { SecHead } from '../components/SecHead';

const COLUMNS: { title: string; items: string[] }[] = [
  { title: 'Coding agents', items: ['Claude Code', 'Codex', 'OpenCode', 'Gemini CLI', 'Kimi CLI', 'Qwen Code', 'Qoder', 'Factory', 'CodeBuddy'] },
  { title: 'Jump back to', items: ['Terminal', 'Ghostty', 'iTerm2', 'WezTerm', 'tmux', 'cmux', 'Kaku'] },
  { title: 'Music', items: ['Spotify', 'Apple Music'] },
];

export default function WorksWith() {
  return (
    <section id="works-with" className="sec sec-ink" aria-labelledby="works-title">
      <div className="frame">
        <SecHead
          num="05" label="Works with" note="Local hooks, no accounts" id="works-title"
          title={<>The tools you already use.</>}
          lede="NotchTune listens to your agents through local hooks and their own session files, then jumps you back to the exact terminal they’re running in."
        />
        <div className="stage index reveal">
          {COLUMNS.map((c) => (
            <div className="index-col" key={c.title}>
              <h3 className="label">{c.title}</h3>
              <ul>{c.items.map((i) => <li key={i}>{i}</li>)}</ul>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
