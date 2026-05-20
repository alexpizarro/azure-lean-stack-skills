import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // In local dev, proxy /api/* to the Azure Functions emulator
      '/api': {
        target: 'http://localhost:7071',
        changeOrigin: true,
      },
    },
  },
})
