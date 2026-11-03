import type { Config } from 'tailwindcss'

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy: { DEFAULT: '#0D1B2A', 700: '#1B2B3F', 500: '#3A4C63', 100: '#E6EAF0', 50: '#F4F6F9' },
        gold: { DEFAULT: '#B8860B', 700: '#946B08', 100: '#F6EBCB' },
      },
      fontFamily: { sans: ['Cairo', 'Tahoma', 'system-ui', 'sans-serif'] },
    },
  },
  plugins: [],
}
export default config
