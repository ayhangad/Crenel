// One place for the links and facts the pages repeat.
export const REPO = 'https://github.com/ayhangad/Crenel';
export const LATEST = `${REPO}/releases/latest`;
export const X_URL = 'https://x.com/ayhangad';
export const X_HANDLE = '@ayhangad';
export const REQUIREMENTS = 'macOS 26 or later · Apple silicon and Intel';
export const dmgUrl = (version: string) => `${REPO}/releases/download/v${version}/Crenel-${version}.dmg`;
export const releaseUrl = (version: string) => `${REPO}/releases/tag/v${version}`;
