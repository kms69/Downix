# Safari Extension — TODO (requires Xcode)

Safari App Extensions cannot be built with SPM/CLI alone; they need an Xcode
project with a `Safari Extension` target.

Planned steps:
1. Create Xcode project wrapping this SPM package.
2. Add Safari Extension target (bundle id `com.downloadmanager.safari-extension`).
3. Reuse `../Chrome/content.js` as the injected script and `../Chrome/popup.html`.
4. Bridge to the app via `downloadmanager://add?url=` (already handled in
   `DownloadManagerApp.swift`) until a native-message handler is added.

Meanwhile Chrome / Brave / Edge / Firefox are fully supported via the
runtime-installed native host (`BrowserIntegrationManager.installNativeHost()`).
