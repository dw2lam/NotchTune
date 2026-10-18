const AGENTS: [string, string?][] = [
  ['Claude Code', 'claude.svg'], ['Codex', 'openai.svg'], ['OpenCode', 'opencode.svg'], ['Gemini CLI', 'googlegemini.svg'],
  ['Kimi CLI', 'kimi.svg'], ['Qwen Code', 'qwen.svg'], ['Qoder'], ['Factory'], ['CodeBuddy'],
];
const TERMINALS = ['Terminal', 'Ghostty', 'iTerm2', 'WezTerm', 'tmux', 'cmux', 'Kaku'];
const MUSIC: [string, string][] = [['Spotify', 'spotify.svg'], ['Apple Music', 'applemusic.svg']];

export default function WorksWith() {
  return (
    <section id="works-with" className="section" aria-labelledby="works-title">
      <div className="wrap">
        <header className="head">
          <h2 id="works-title" className="h2 reveal">Works with the tools you already&nbsp;use.</h2>
        </header>
        <div className="works glass reveal">
          <div className="works-row">
            <h3>Coding agents</h3>
            <ul className="works-list">
              {AGENTS.map(([name, logo]) => (
                <li key={name}>{logo && <img src={`/assets/logos/${logo}`} alt="" width={16} height={16} />}{name}</li>
              ))}
            </ul>
          </div>
          <div className="works-row">
            <h3>Jump back to</h3>
            <ul className="works-list">
              {TERMINALS.map((name) => <li key={name}>{name}</li>)}
            </ul>
          </div>
          <div className="works-row">
            <h3>Music</h3>
            <ul className="works-list">
              {MUSIC.map(([name, logo]) => (
                <li key={name}><img src={`/assets/logos/${logo}`} alt="" width={16} height={16} />{name}</li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </section>
  );
}
