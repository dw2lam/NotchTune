import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Hashed bundles get their own folder, apart from public/assets, so that
  // vercel.json can cache only these forever.
  build: { assetsDir: 'build' },
  server: { port: 8745, host: true },
  preview: { port: 8745, host: true },
});
