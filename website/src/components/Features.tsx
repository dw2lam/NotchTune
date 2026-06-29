import { IslandTop, TabBar, UsageChip, MusicView } from './IslandParts';

export default function Features() {
  return (
    <section id="features" className="section">
      <div className="section-head reveal">
        <h2>One island. Every moment that matters.</h2>
        <p>NotchTune switches itself between music and agents, so the notch always shows the thing you need right now.</p>
      </div>

      {/* Music */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Music</span>
          <h3>Full playback, right in the glass.</h3>
          <p>Control Spotify or Apple Music without leaving your work — artwork, scrubbable progress, shuffle, repeat, love, and volume, all inside a liquid-glass panel that lives where your eyes already are.</p>
        </div>
        <div className="feature-stage">
          <div className="scene scene-music">
            <div className="island island-expanded glass-deep">
              <IslandTop><UsageChip name="Claude" time="5h" pct="41%" /></IslandTop>
              <TabBar active="music" />
              <MusicView />
            </div>
          </div>
        </div>
      </div>

      {/* Agents */}
      <div className="feature feature-rev reveal">
        <div className="feature-text">
          <span className="kicker">Agents</span>
          <h3>Every state, at a glance.</h3>
          <p>Watch your terminal-native coding agents live. The status dot tells you exactly where each one is — before you've even switched windows.</p>
          <div className="states-legend">
            <span><span className="s-dot running" /> Working</span>
            <span><span className="s-dot waiting" /> Waiting on you</span>
            <span><span className="s-dot done" /> Done</span>
          </div>
        </div>
        <div className="feature-stage">
          <div className="scene scene-agents">
            <div className="island island-expanded glass-deep">
              <IslandTop>
                <UsageChip name="Claude" time="5h" pct="78%" tone="u-warn" />
                <UsageChip name="Codex" time="7d" pct="62%" />
              </IslandTop>
              <TabBar active="agents" />
              <ul className="rows">
                <li className="row">
                  <span className="rdot on" />
                  <div className="rmain">
                    <div className="rtitle"><b>api</b> · refactoring the bridge transport</div>
                    <div className="rprev"><span className="who">You:</span> make BridgeServer dispatch on a background queue…</div>
                    <div className="rstate">running</div>
                  </div>
                  <div className="rmeta"><div className="rbadges"><span className="rb">Claude Code</span><span className="rb">Ghostty</span></div><span className="rtime">‹1m</span></div>
                </li>
                <li className="row rchild">
                  <span className="rdot on" />
                  <div className="rmain"><div className="rtitle">↳ subagent · searching the codebase</div></div>
                  <div className="rmeta"><span className="rtime">3s</span></div>
                </li>
                <li className="row">
                  <span className="rdot wait" />
                  <div className="rmain">
                    <div className="rtitle"><b>web</b> · ready to deploy to staging?</div>
                    <div className="rstate">waiting for you</div>
                  </div>
                  <div className="rmeta"><div className="rbadges"><span className="rb">Gemini</span><span className="rb">WezTerm</span></div><span className="rtime">18s</span></div>
                </li>
                <li className="row">
                  <span className="rdot done" />
                  <div className="rmain"><div className="rtitle"><b>infra</b> · deployed to staging ✓</div></div>
                  <div className="rmeta"><div className="rbadges"><span className="rb">Codex</span><span className="rb">tmux</span></div><span className="rtime">2m</span></div>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>

      {/* Approvals */}
      <div className="feature reveal">
        <div className="feature-text">
          <span className="kicker">Approvals &amp; questions</span>
          <h3>Say yes without breaking flow.</h3>
          <p>When an agent needs permission or has a question, the island grows into a notification panel right under the notch. Approve, deny, or answer in place — then it round-trips straight back to the process that asked.</p>
        </div>
        <div className="feature-stage">
          <div className="scene scene-approve">
            <div className="island island-expanded glass-deep island-notify">
              <IslandTop><UsageChip name="Claude" time="5h" pct="41%" /></IslandTop>
              <div className="notify">
                <div className="n-head"><span className="s-dot waiting" /> <b>api</b> · Claude Code wants to run</div>
                <code className="n-code">rm -rf ./build &amp;&amp; swift build -c release</code>
                <div className="n-actions">
                  <button className="btn btn-deny">Deny</button>
                  <button className="btn btn-allow">Allow</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* secondary grid */}
      <div className="grid3 reveal">
        <article className="card glass">
          <div className="card-ico">🔔</div>
          <h4>Quiet by default</h4>
          <p>Configurable system sounds for permission and completion events — or mute it entirely. English and 简体中文 built in.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">↩︎</div>
          <h4>Jump back to the right window</h4>
          <p>One click returns focus to the exact terminal — Ghostty, iTerm2, WezTerm, tmux, Terminal.app, cmux, and more.</p>
        </article>
        <article className="card glass">
          <div className="card-ico">🖥️</div>
          <h4>Follows your focus</h4>
          <p>The island moves to whatever display you're working on, and adapts as it goes — a real notch surface on MacBooks, a clean top-center bar on external and non-notch screens. It even keeps a separate look for each.</p>
        </article>
      </div>
    </section>
  );
}
