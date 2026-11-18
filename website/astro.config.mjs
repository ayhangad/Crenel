// @ts-check
import { defineConfig } from 'astro/config';

// The domain may change (crenel.ayhan.fyi today), so it comes from the environment.
// Set SITE_URL in Dokploy; without it the site still builds, with relative URLs.
export default defineConfig({
  site: process.env.SITE_URL || undefined,
  trailingSlash: 'never',
  build: { format: 'file' },
  vite: { server: { fs: { allow: ['..'] } } },
});
