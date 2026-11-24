// Builds the release timeline: the markdown in docs/releases, newest first, with the date
// and state of each version taken from GitHub at build time (git as the fallback).
import { getCollection, type CollectionEntry } from 'astro:content';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export type Release = {
  entry: CollectionEntry<'releases'>;
  version: string;
  title: string;
  date?: Date;
  published: boolean;
  latest: boolean;
};

type GitHubRelease = { tag_name: string; published_at: string | null; draft: boolean; prerelease: boolean };

const compare = (a: string, b: string) => {
  const pa = a.split('.').map(Number), pb = b.split('.').map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return d;
  }
  return 0;
};

async function githubReleases(): Promise<GitHubRelease[]> {
  // The Docker build downloads the list once (see Dockerfile); read that copy when present.
  const file = process.env.GITHUB_RELEASES_FILE;
  if (file && existsSync(file)) {
    try {
      const list = JSON.parse(readFileSync(file, 'utf8'));
      if (Array.isArray(list)) return list as GitHubRelease[];
    } catch {
      // Fall through to the API.
    }
  }
  try {
    const headers: Record<string, string> = { Accept: 'application/vnd.github+json', 'User-Agent': 'crenel-website-build' };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    const res = await fetch('https://api.github.com/repos/ayhangad/Crenel/releases?per_page=100', { headers });
    if (!res.ok) return [];
    return (await res.json()) as GitHubRelease[];
  } catch {
    return [];
  }
}

function gitDate(version: string): Date | undefined {
  try {
    const cwd = fileURLToPath(new URL('../../../', import.meta.url));
    const out = execFileSync('git', ['log', '--diff-filter=A', '--format=%cI', '--', `docs/releases/${version}.md`], { cwd, encoding: 'utf8' }).trim();
    const last = out.split('\n').filter(Boolean).pop();
    return last ? new Date(last) : undefined;
  } catch {
    return undefined;
  }
}

let cached: Promise<Release[]> | undefined;

export function getReleases(): Promise<Release[]> {
  cached ??= (async () => {
    const [entries, remote] = await Promise.all([getCollection('releases'), githubReleases()]);
    const list = entries
      .map((entry) => {
        const version = entry.id.replace(/\.md$/, '');
        const gh = remote.find((r) => r.tag_name === `v${version}` && !r.draft);
        const heading = entry.body?.match(/^#\s+(.+)$/m)?.[1]?.trim();
        return {
          entry,
          version,
          title: heading ?? `Crenel ${version}`,
          date: gh?.published_at ? new Date(gh.published_at) : gitDate(version),
          published: Boolean(gh?.published_at),
          latest: false,
        } satisfies Release;
      })
      .sort((a, b) => compare(b.version, a.version));
    const newestPublished = list.find((r) => r.published);
    if (newestPublished) newestPublished.latest = true;
    return list;
  })();
  return cached;
}

export const formatDate = (d?: Date) =>
  d ? d.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' }) : '';
