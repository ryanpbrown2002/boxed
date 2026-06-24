import { test, expect, _electron as electron } from '@playwright/test'

// Some environments (CI sandboxes) export ELECTRON_RUN_AS_NODE=1, which makes
// Electron boot as plain Node and `require('electron')` return a path string.
// Strip it so the app launches as a real Electron process.
function electronEnv(): Record<string, string> {
  const env: Record<string, string> = {}
  for (const [k, v] of Object.entries(process.env)) {
    if (k !== 'ELECTRON_RUN_AS_NODE' && v !== undefined) env[k] = v
  }
  return env
}

// Requires a prior `npm run build` (the test:e2e script does this for you).
test('boxed launches and shows its workspace shelf', async () => {
  const app = await electron.launch({ args: ['out/main/index.js'], env: electronEnv() })
  const window = await app.firstWindow()

  // The brand wordmark in the shelf proves the renderer mounted.
  await expect(window.locator('.brand h1')).toHaveText('boxed')

  // The default workspace renders two boxes side by side.
  await expect(window.locator('.box')).toHaveCount(2)

  await app.close()
})
