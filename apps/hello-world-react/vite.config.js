import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  base: '/', // Ensure assets are referenced from root for CloudFront
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false, // Disable source maps for production deployment
    rollupOptions: {
      output: {
        manualChunks: undefined, // Simplify chunk strategy for CloudFront
      }
    }
  }
})
