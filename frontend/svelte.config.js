import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    // The Node adapter produces the SSR server that owns Railway's public port.
    adapter: adapter({ precompress: true })
  }
};

export default config;
