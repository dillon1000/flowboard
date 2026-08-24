import adapter from '@sveltejs/adapter-node';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  kit: {
    // The Node adapter produces the SSR server that owns Railway's public port.
    adapter: adapter({ precompress: true }),
    // OAuth token exchange is intentionally a cross-origin form POST from public
    // MCP clients. Browser sessions remain SameSite=Lax and Vapor authorizes every
    // state-changing application request.
    csrf: { checkOrigin: false }
  }
};

export default config;
