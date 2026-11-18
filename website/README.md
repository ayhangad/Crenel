# Crenel website

The public site: a home page and a release timeline. Astro, static output, no client
framework. The design follows the app's "night drive" language (`../docs/DESIGN.md`) on
the light wallpaper of the promo film.

```sh
cd website
npm install
npm run dev        # http://localhost:4321
npm run build      # static site in dist/
```

Needs Node 22.23 or later (see `.nvmrc`).

## Content

- **Releases** come from `../docs/releases/<version>.md`, the same notes the release
  script puts into Sparkle's appcast. Adding a file adds a release to `/releases`. The date
  and the "Latest" mark come from GitHub Releases at build time (git is the fallback), so
  rebuild the site after publishing a release. A version without a GitHub release shows
  as "Coming soon".
- **Media** in `public/media/` are web copies of `../docs/media/` (WebP, and the promo film
  re-encoded to about 2 MB). Regenerate them when the renders change.
- **Contact** is X only (`src/lib/site.ts`). No email on the site.

## Deploy (Dokploy)

- Build type: Dockerfile. Dockerfile path `website/Dockerfile`, build context `.` (the repo
  root, so `docs/releases` is included).
- Build argument `SITE_URL`, for example `https://crenel.ayhan.fyi`. It sets canonical and
  Open Graph URLs; the domain is not written anywhere else in the code.
- The container serves on port 80 (nginx).
