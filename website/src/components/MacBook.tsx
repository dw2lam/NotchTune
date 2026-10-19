import type { ReactNode } from 'react';

/* A 14-inch MacBook Pro seen straight on, drawn to its real proportions.
   Everything on the screen is sized in --pt, one macOS point at this
   size, so the real captures inside sit at true scale against the notch.
   The lid opens and the screen wakes when the page loads. */
export default function MacBook({ label, children }: { label: string; children: ReactNode }) {
  return (
    <figure className="mbp" aria-label={label}>
      <div className="mbp-lid">
        <div className="mbp-screen">
          <img
            className="mbp-wall"
            src="/assets/wallpaper-2000.webp"
            srcSet="/assets/wallpaper-1100.webp 1100w, /assets/wallpaper-2000.webp 2000w, /assets/wallpaper-2400.webp 2365w"
            sizes="(max-width: 719px) 200vw, 1300px"
            alt=""
            decoding="async"
          />
          <div className="mbp-menubar" aria-hidden="true">
            <span className="mbp-menu">
              <b>Ghostty</b><span>Shell</span><span>Edit</span><span>View</span><span>Window</span><span>Help</span>
            </span>
            <span className="mbp-status">
              <svg viewBox="0 0 24 12" className="mbp-battery"><rect x="0.5" y="0.5" width="20" height="11" rx="3" fill="none" stroke="currentColor" strokeOpacity="0.5" /><rect x="2" y="2" width="14" height="8" rx="1.6" fill="currentColor" /><rect x="21.6" y="4" width="1.6" height="4" rx="0.8" fill="currentColor" fillOpacity="0.5" /></svg>
              <svg viewBox="0 0 16 12" className="mbp-wifi"><path d="M8 11.2 5.6 8.6a3.4 3.4 0 0 1 4.8 0L8 11.2Zm-4.2-4.4-1.4-1.5a7.9 7.9 0 0 1 11.2 0l-1.4 1.5a5.9 5.9 0 0 0-8.4 0ZM.6 3.4 0 2.8 0 2.7a11.3 11.3 0 0 1 16 0l-.6.7-.8.8a9.6 9.6 0 0 0-13.2 0l-.8-.8Z" fill="currentColor" /></svg>
              <span>Sat 18 Oct</span><span>9:41</span>
            </span>
          </div>
          <div className="mbp-notch" />
          {children}
        </div>
      </div>
      <div className="mbp-base" />
    </figure>
  );
}
