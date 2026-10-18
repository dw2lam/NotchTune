/* The fixed night scene behind every pane: stars, a low moon, its path on
   still water, and soft pools of light for the glass to catch. */
export default function Backdrop() {
  return (
    <div className="backdrop" aria-hidden="true">
      <div className="backdrop-stars" />
      <div className="backdrop-pool p1" />
      <div className="backdrop-pool p2" />
      <div className="backdrop-pool p3" />
      <div className="backdrop-horizon" />
      <div className="backdrop-moon" />
      <div className="backdrop-water" />
      <div className="backdrop-glint" />
    </div>
  );
}
