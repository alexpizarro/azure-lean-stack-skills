import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
//
// /api/* is proxied so the SPA can call the API with a relative URL in every mode:
//   npm run dev       → http://localhost:7071   (local Functions host — the fully-offline stack)
//   npm run dev:test  → the deployed TEST SWA   (UI-only work against real test data; no local API/SQL)
// VITE_PROXY_TARGET is set by the dev:test script in package.json. Never point it at prod.
const proxyTarget = process.env.VITE_PROXY_TARGET || 'http://localhost:7071'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': {
        target: proxyTarget,
        changeOrigin: true,
      },
    },
  },
})
