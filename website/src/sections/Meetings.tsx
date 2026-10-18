import { Shot } from '../components/Shot';
import { Feature, Crop } from '../components/Feature';

export default function Meetings() {
  return (
    <Feature
      id="meetings"
      title="Meetings, a few minutes early."
      line="Turn it on, and the notch counts down to your next call with a Join button, then stays quiet while you’re in it. Your calendars never leave your Mac."
    >
      <div className="meeting">
        <div className="edge">
          <Crop><Shot name="pill-meeting" alt="The closed notch four minutes before Design review, 09:53 to 10:23, with a video call mark." /></Crop>
        </div>
        <Crop>
          <Shot name="banner" alt="Opened, the island shows the Design review banner: in 4 minutes, 09:54 to 10:24, with Join." />
        </Crop>
      </div>
    </Feature>
  );
}
