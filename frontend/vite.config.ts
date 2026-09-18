import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// GitHub Pages project sites live at /<repo>/ — set VITE_BASE in CI.
const base = process.env.VITE_BASE || '/'

export default defineConfig({
  plugins: [react()],
  base,
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
