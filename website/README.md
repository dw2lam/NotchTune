# NotchTune — marketing site

The landing page for NotchTune. A React and Vite app: a scroll story on a MacBook built from real captures of the app, then a
download section that reads the latest release from the GitHub API.

The code is in `src/` (`sections/`, `components/`, `hooks/`), and the images are
in `public/assets/`.

## Run locally

```bash
cd website
npm install
npm run dev
```

`npm run build` writes the production site to `dist/`.

## Deploy on Vercel

This site lives in a subfolder of the app repo, so point Vercel at it:

1. Import the `dw2lam/NotchTune` repo into Vercel.
2. **Settings → General → Root Directory** → set to `website`.
3. `vercel.json` sets the Vite framework, the build, clean URLs and long-cache
   headers for assets.

Production tracks `main`; pushes to other branches get preview URLs.

## Notes

- `src/hooks/useLatestRelease.ts` reads
  `https://api.github.com/repos/dw2lam/NotchTune/releases/latest` and falls back
  to a baked-in version if the API is unreachable. Bump that version with each
  release.
