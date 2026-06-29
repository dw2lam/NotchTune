import { useRef } from 'react';
import { useCycle } from '../hooks/useCycle';
import { IslandTop, TabBar, UsageChip, MusicView } from './IslandParts';
import { Sprite, SpriteRun } from './Sprite';

export default function Adapts() {
  const deckRef = useRef<HTMLDivElement>(null);
  const cnotchRef = useRef<HTMLDivElement>(null);
  const open = useCycle(['music', 'agents', 'approve', 'music'], 2600, deckRef);
  const closed = useCycle(['music', 'agents', 'idle', 'music', 'agents'], 2400, cnotchRef);

  const on = (a: string, b: string) => (a === b ? ' active' : '');

  return (
    <section id="adapts" className="section">
      <div className="section-head reveal">
        <h2>It adapts to the moment.</h2>
        <p>Open, the island switches itself between music, agents, and prompts. Closed, it keeps you posted from inside the notch — you never go looking.</p>
      </div>

      <div className="adapts-grid reveal">
        <div className="adapts-col">
          <div className="adapts-cap">Open · switches itself</div>
          <div className="switch-wrap">
            <div className="scene scene-switch">
              <div className="island-deck" ref={deckRef}>
                {/* music */}
                <div className={`island island-expanded glass-deep deck-state${on(open, 'music')}`}>
                  <IslandTop><UsageChip name="Claude" time="5h" pct="41%" /></IslandTop>
                  <TabBar active="music" />
                  <MusicView />
                </div>
                {/* agents */}
                <div className={`island island-expanded glass-deep deck-state${on(open, 'agents')}`}>
                  <IslandTop><UsageChip name="Claude" time="5h" pct="41%" /></IslandTop>
                  <TabBar active="agents" />
                  <ul className="rows">
                    <li className="row">
                      <span className="rdot on" />
                      <div className="rmain"><div className="rtitle"><b>api</b> · running the test suite</div><div className="rstate">running</div></div>
                      <div className="rmeta"><div className="rbadges"><span className="rb">Claude Code</span><span className="rb">Ghostty</span></div><span className="rtime">‹1m</span></div>
                    </li>
                    <li className="row">
                      <span className="rdot on" />
                      <div className="rmain"><div className="rtitle"><b>web</b> · 2 subagents working</div><div className="rstate">running</div></div>
                      <div className="rmeta"><div className="rbadges"><span className="rb">Gemini</span><span className="rb">WezTerm</span></div><span className="rtime">5s</span></div>
                    </li>
                  </ul>
                </div>
                {/* approve */}
                <div className={`island island-expanded glass-deep island-notify deck-state${on(open, 'approve')}`}>
                  <IslandTop><UsageChip name="Claude" time="5h" pct="41%" /></IslandTop>
                  <div className="notify">
                    <div className="n-head"><span className="s-dot waiting" /> <b>api</b> · Claude Code wants to run</div>
                    <code className="n-code">git push origin main</code>
                    <div className="n-actions"><button className="btn btn-deny">Deny</button><button className="btn btn-allow">Allow</button></div>
                  </div>
                </div>
              </div>
            </div>
            <div className="switch-legend">
              <span className={`dl-pill${on(open, 'music')}`}><span className="dl-ico">♫</span> Now playing</span>
              <span className={`dl-pill${on(open, 'agents')}`}><span className="dl-ico dl-run" /> Agents working</span>
              <span className={`dl-pill${on(open, 'approve')}`}><span className="dl-ico dl-wait" /> Needs you</span>
            </div>
          </div>
        </div>

        <div className="adapts-col">
          <div className="adapts-cap">Closed · still watching</div>
          <div className="closed-wrap">
            <div className="closed-scene">
              <div className="cnotch" ref={cnotchRef}>
                <div className="cn-wing cn-left">
                  <span className={`cn-slot${on(closed, 'music')}`}><span className="cn-art" /></span>
                  <span className={`cn-slot${on(closed, 'agents')}`}><SpriteRun char="dino" className="cn-sprite cn-dance" /></span>
                  <span className={`cn-slot${on(closed, 'idle')}`}><Sprite char="dino" className="cn-sprite" /></span>
                </div>
                <span className="cn-core" />
                <div className="cn-wing cn-right">
                  <span className={`cn-slot${on(closed, 'music')}`}><span className="eq"><i /><i /><i /><i /><i /></span></span>
                  <span className={`cn-slot${on(closed, 'agents')}`}><span className="cn-tiles"><i /><i className="t2" /></span></span>
                  <span className={`cn-slot${on(closed, 'idle')}`} />
                </div>
              </div>
            </div>
            <div className="switch-legend">
              <span className={`dl-pill${on(closed, 'music')}`}><span className="dl-ico">♫</span> Now playing</span>
              <span className={`dl-pill${on(closed, 'agents')}`}><span className="dl-ico dl-agent" /> Agents live</span>
              <span className={`dl-pill${on(closed, 'idle')}`}><span className="dl-ico cn-idle-dot" /> Idle</span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
