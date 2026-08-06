import { resolve } from 'node:path';
import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    outDir: 'dist',
    emptyOutDir: false,
    lib: {
      entry: resolve(import.meta.dirname, 'src/content-script.ts'),
      formats: ['iife'],
      name: 'FocalpointCanvasContent',
      fileName: () => 'content-script.js'
    }
  }
});
