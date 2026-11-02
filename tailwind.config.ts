import type { Config } from 'tailwindcss'

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        navy: { DEFAULT: '#0A1628', 700: '#16263F', 500: '#3A4C63', 100: '#E6EAF0', 50: '#F8F6F1', mid: '#1B3F8B' },
        gold: { DEFAULT: '#C6922A', 700: '#8B6914', 100: '#F6EBCB', light: '#F5D06A' },
      },
      fontFamily: { sans: ['Cairo', 'Tahoma', 'system-ui', 'sans-serif'] },
    },
  },
  plugins: [],
}
export default config
