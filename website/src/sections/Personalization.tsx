import { Shot } from '../components/Shot';
import { Feature, Crop } from '../components/Feature';

export default function Personalization() {
  return (
    <Feature
      id="personalize" layout="wide"
      title="Make it yours."
      line="Pick one of twenty characters and how lively it is. Style the MacBook notch and an external display apart, or turn on Sync and change both at once."
    >
      <Crop to={604} h={700}>
        <Shot
          name="settings" className="reflect"
          alt="NotchTune Settings on Personalization: live previews of the MacBook notch and an external display, linked with Sync on, then a grid of twenty pixel characters with Dino selected, and Character motion set to Calm."
        />
      </Crop>
    </Feature>
  );
}
