import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

/** GitHub Pages project sites live under /<repo>/; local/dev stays at /. */
function pagesBase(): string {
  const raw = process.env.VITE_BASE
  if (!raw) return '/'
  return raw.endsWith('/') ? raw : `${raw}/`
}

export default defineConfig({
  plugins: [react()],
  base: pagesBase(),
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
      '/health': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
})
