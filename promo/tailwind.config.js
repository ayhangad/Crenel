// Colours and font copied from the tailwind.config in docs/design/crenel-prototype.html.
/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: { extend: {
    fontFamily: { sans: ['Geist', 'ui-sans-serif', 'system-ui'] },
    colors: {
      ink: { 1: '#f3f1ec', 2: '#aaa7a1', 3: '#76736e', 4: '#4c4a47', 5: '#2e2d2b' },
      signal: '#ffad33',
      live: '#ff5a47',
      ok: '#34e6cb',
    },
  } },
}
