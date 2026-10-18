import { IslandPanel, UsageCycler, KeyHint } from '../mock';
import { JumpIcon, ReplyIcon, ChevronLeftIcon, ChevronRightIcon } from '../mock/icons';
import { USAGE_PROVIDERS, MODEL_WEEKLY } from '../lib/demoData';
import { usePhone } from '../hooks/useMedia';
import { Shot } from '../components/Shot';
import { SecHead } from '../components/SecHead';

/* The completion card as 2.1.5 draws it (CompletionToastView with
   TaskSummaryLine under the header). */
function CompletionCard() {
  return (
    <div className="nt-toast">
      <div className="nt-toast-head">
        <span className="nt-toast-dot" />
        <b>Codex finished</b>
        <span className="nt-toast-ws">api</span>
        <span className="nt-toast-meta">Ghostty &lt;1m</span>
      </div>
      <div className="tsum">
        <span className="dim">
          <svg viewBox="0 0 16 16"><path d="M10.8 2.6l2.6 2.6M3 13l1-3.6 7.3-7.3 2.6 2.6L6.6 12z" /></svg>
          <b>Edited 4 files</b>
        </span>
        <span className="ok">
          <svg viewBox="0 0 16 16"><path d="M8 1.3a6.7 6.7 0 1 1 0 13.4A6.7 6.7 0 0 1 8 1.3Zm3 4.3L7 9.6 5 7.6l-1 1 3 3 5-5Z" /></svg>
          <b>Tests passed</b>
        </span>
        <span className="dim">
          <svg viewBox="0 0 16 16"><path d="M8 2a6 6 0 1 1 0 12A6 6 0 0 1 8 2ZM8 5v3.2l2 1.4" /></svg>
          <b>3m 12s</b>
        </span>
      </div>
      <div className="nt-toast-prompt">You: Make BridgeServer dispatch on a background queue.</div>
      <p className="nt-toast-excerpt">
        Done. BridgeServer now hands every request to a serial background queue, and the four tests that
        covered the old path pass on the new one.
      </p>
      <div className="nt-toast-actions">
        <span className="nt-gbtn nt-gbtn-sm nt-gbtn-primary"><JumpIcon /> Jump to Ghostty <KeyHint keys="⏎" /></span>
        <span className="nt-gbtn nt-gbtn-sm nt-gbtn-secondary"><ReplyIcon /> Reply</span>
        <span className="nt-toast-spacer" />
        <span className="nt-toast-queue">
          <span className="nt-gdisc nt-gdisc-sm"><ChevronLeftIcon /></span>
          <span>1/2</span>
          <span className="nt-gdisc nt-gdisc-sm"><ChevronRightIcon /></span>
        </span>
        <span className="nt-toast-all">All 9 sessions</span>
      </div>
    </div>
  );
}

export default function Summaries() {
  const phone = usePhone();
  return (
    <section id="summaries" className="sec sec-paper" aria-labelledby="summaries-title">
      <div className="frame">
        <SecHead
          num="04" label="Finished tasks" note="New in 2.1.5" id="summaries-title"
          title={<>Know what got done.</>}
          lede="When an agent finishes, a small card says what changed: files edited, tests run and whether they passed, and how long it took. It’s worked out on your Mac from the session itself."
        />
        <div className="stage edge reveal">
          <div className="hang at-end">
            <Shot label="A completion card: Codex finished in api. Edited 4 files, tests passed, 3 minutes 12 seconds, with Jump to Ghostty and Reply.">
              <div className="zoom-shot">
                <IslandPanel usage={<UsageCycler providers={USAGE_PROVIDERS} initial={1} />} modelWeekly={MODEL_WEEKLY} glass="off" showNotchGap={!phone}>
                  <CompletionCard />
                </IslandPanel>
              </div>
            </Shot>
          </div>
          <p className="fig"><b>Fig. 04</b>Return jumps back to the right terminal. Usage limits and their resets sit in the header.</p>
        </div>
      </div>
    </section>
  );
}
