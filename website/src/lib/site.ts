// One place for the links and facts the pages repeat.
export const REPO = 'https://github.com/ayhangad/Crenel';
export const LATEST = `${REPO}/releases/latest`;
/** Downloads the newest DMG straight away. Every release also carries it as Crenel.dmg. */
export const LATEST_DMG = `${REPO}/releases/latest/download/Crenel.dmg`;
export const X_URL = 'https://x.com/ayhangad';
export const X_HANDLE = '@ayhangad';
export const REQUIREMENTS = 'macOS 26 or later · Apple silicon and Intel';
export const releaseUrl = (version: string) => `${REPO}/releases/tag/v${version}`;
