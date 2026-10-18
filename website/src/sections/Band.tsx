import { PlateImage } from '../components/Plate';

/* A cropped strip of the oasis between sections: the horizon, the palms'
   reflections and the moon's path on the water. */
export default function Band() {
  return (
    <div className="plate plate-band" aria-hidden="true">
      <PlateImage />
    </div>
  );
}
