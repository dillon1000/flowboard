import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://127.0.0.1:8080',
      '/login': 'http://127.0.0.1:8080',
      '/register': 'http://127.0.0.1:8080',
      '/logout': 'http://127.0.0.1:8080',
      '/app': 'http://127.0.0.1:8080'
    }
  },
  build: {
    // Vapor serves this behavior and style bundle beside the Leaf pages. The
    // generated index is unused, but Vite keeps it as the dependency entrypoint.
    outDir: '../backend/Public',
    emptyOutDir: false,
    rollupOptions: {
      output: {
        entryFileNames: 'assets/app.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name][extname]'
      }
    }
  }
});
