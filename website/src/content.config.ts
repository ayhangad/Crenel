// Release notes live in the monorepo's docs/releases/<version>.md: the same files the
// release script embeds into Sparkle's appcast. Adding a file there adds it here.
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';

const releases = defineCollection({
  loader: glob({
    pattern: '*.md',
    base: '../docs/releases',
    // Keep the version as the id ("1.0", not the slug "10").
    generateId: ({ entry }) => entry.replace(/\.md$/, ''),
  }),
});

export const collections = { releases };
