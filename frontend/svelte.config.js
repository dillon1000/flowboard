import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    // The Node adapter produces the SSR server that owns Railway's public port.
    adapter: adapter({ precompress: true }),
    // Keep product images in one source directory while SvelteKit takes over serving them.
    files: {
      assets: '../backend/Public'
    }
  }
};

export default config;
