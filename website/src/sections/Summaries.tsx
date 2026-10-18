import { Shot } from '../components/Shot';
import { Feature, Crop } from '../components/Feature';

export default function Summaries() {
  return (
    <Feature
      id="summaries"
      title="Every finished task, in one line."
      line="When an agent finishes, a card says what changed: files edited, whether the tests passed, and how long it took. Return jumps back to the terminal."
    >
      <Crop>
        <Shot
          name="summary" className="reflect"
          alt="A completion card: Claude Code finished in web. Edited 4 files, tests passed, 3 minutes 12 seconds. The reply says checkout now loads in 1.2 seconds instead of 3.4, with Jump to Ghostty and Reply."
        />
      </Crop>
    </Feature>
  );
}
