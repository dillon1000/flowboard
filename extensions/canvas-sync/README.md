# Focalpoint Canvas Sync

This private Chrome extension reads documented Canvas course and assignment APIs through the signed-in Canvas page. It sends a complete read-only snapshot to one Focalpoint connection. It does not read or store the Canvas password or session cookie.

## Build and install

1. Run `pnpm install` and `pnpm build` in this directory.
2. Open `chrome://extensions` in a Chrome-based browser.
3. Enable Developer mode.
4. Select **Load unpacked**, then select this package's `dist` directory.
5. Create a Canvas connection in Focalpoint under **Settings → Integrations**.
6. Open the extension popup. Enter the exact Canvas origin, the Focalpoint origin, and the one-time `fcs_` sync key.
7. Open a signed-in page on the configured Canvas site. The extension will sync once, or you can select **Sync now**.

The extension requests access only to the two exact HTTPS origins that you save. A changed configuration removes access to the old origins. Disconnect the connection in Focalpoint when you no longer want the extension to sync.
