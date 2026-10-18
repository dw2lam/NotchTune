/* The fixed night scene behind every pane: a moonlit desert oasis
   (generated with Antigravity), shaded toward the top and bottom so the
   glass and the type read, and drifting very slowly. */
export default function Backdrop() {
  return (
    <div className="backdrop" aria-hidden="true">
      <div className="backdrop-scene" />
      <div className="backdrop-shade" />
    </div>
  );
}
