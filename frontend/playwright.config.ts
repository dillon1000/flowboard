import { defineConfig, devices } from '@playwright/test';

const backendPort = 18080;
const frontendPort = 15173;

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  timeout: 60_000,
  expect: { timeout: 12_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: `http://127.0.0.1:${frontendPort}`,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'retain-on-failure'
  },
  webServer: [
    {
      command: `swift run App serve --env development --hostname 127.0.0.1 --port ${backendPort}`,
      cwd: '../backend',
      env: {
        DATABASE_PATH: process.env.FLOWBOARD_E2E_DATABASE_PATH ?? '/tmp/focalpoint-playwright.sqlite'
      },
      url: `http://127.0.0.1:${backendPort}/health`,
      reuseExistingServer: false,
      timeout: 180_000
    },
    {
      command: `pnpm dev --host 127.0.0.1 --port ${frontendPort}`,
      cwd: '.',
      env: { BACKEND_URL: `http://127.0.0.1:${backendPort}` },
      url: `http://127.0.0.1:${frontendPort}/health`,
      reuseExistingServer: false,
      timeout: 120_000
    }
  ],
  projects: [
    {
      name: 'desktop-chrome',
      use: { ...devices['Desktop Chrome'], channel: 'chrome', viewport: { width: 1440, height: 960 } }
    }
  ]
});
