We have a native macOS SwiftUI + AppKit app called WindowPane.

Current architecture:
- AppDelegate creates a WindowController.
- WindowController owns a custom OverlayWindow.
- OverlayRootView is hosted in an NSHostingView.
- The app runs as an accessory/menu-bar utility with no Dock icon.
- There is an NSStatusItem menu bar item.
- Camera preview is already working.
- Borderless floating window and custom resize behavior are already working.
- Overlay-style fullscreen behavior is already working.
- Do not use native macOS fullscreen Spaces.

Goal:
Add a simple core Settings system for WindowPane.

Important output policy:
- Do not print full file contents in the TUI unless explicitly requested.
- Edit files directly.
- After editing, summarize:
  1. files changed
  2. behavior implemented
  3. commands to build/test
  4. any known limitations

Settings requirements:
1. Add a Settings window/panel using SwiftUI.
2. Settings should be opened by:
   - Command + Shift + S while the app/window is focused
   - selecting “Settings” from the menu bar item menu
3. Keep the app as an accessory/menu-bar utility. Do not bring back the Dock icon.
4. Keep the menu bar item persistent.
5. Simplify the menu bar item menu so it only contains:
   - Settings
   - separator
   - Quit WindowPane
6. Remove the current “Show WindowPane” menu item.
7. Clicking Settings should show the settings window and bring it forward.
8. Settings window should be normal enough to close/reopen, but lightweight and utility-like.

Settings to implement:
General:
- Show on all Spaces: Bool
- Remember last window position: Bool
- Remember last window size: Bool

Window:
- Rounded corner radius: Double slider
- Window shadow: Bool

Camera:
- Mirror camera: Bool
- Camera device picker

Fullscreen:
- Fullscreen keyboard shortcut
- Escape exits fullscreen: Bool

Persistence:
1. Persist settings using UserDefaults or @AppStorage.
2. Use a simple SettingsStore / ObservableObject if helpful.
3. Do not introduce a database.
4. Do not introduce third-party dependencies.
5. On app launch, apply persisted settings to the window and camera behavior.
6. When settings change, apply them live where reasonable.

Behavior details:
- “Show on all Spaces” should toggle the appropriate NSWindow collectionBehavior behavior.
- “Remember last window position” should save and restore window origin.
- “Remember last window size” should save and restore window size.
- Window frame should be saved when the window moves/resizes, but avoid excessive complexity.
- Rounded corner radius should update the SwiftUI overlay shape live.
- Window shadow should map to NSWindow.hasShadow.
- Mirror camera should update the camera preview transform/preview behavior live.
- Camera device picker should list available video capture devices and allow switching cameras.
- Fullscreen keyboard shortcut can be app-local/focused for now. Do not implement a global hotkey that requires Accessibility permissions.
- Escape should exit overlay fullscreen only if “Escape exits fullscreen” is enabled.

Architecture expectations:
- Settings state should not be scattered randomly.
- Prefer a small WindowPaneSettings or SettingsStore object.
- WindowController should remain responsible for NSWindow-level behavior.
- Camera service/view model should remain responsible for camera-device selection and mirroring.
- SwiftUI settings views should bind to settings state and send intent cleanly.
- Avoid rewriting the existing camera/session/fullscreen/resize systems unless needed.

Suggested files/classes:
- SettingsStore.swift
- SettingsView.swift
- SettingsWindowController.swift, if useful
- Updates to AppDelegate.swift for the simplified status menu and opening settings
- Updates to WindowController.swift to apply settings
- Updates to OverlayRootView.swift for corner radius binding
- Updates to camera service/preview code for mirror/device picker

Non-goals:
- Do not add brightness/contrast/exposure yet.
- Do not add Core Image filters yet.
- Do not add background blur or backdrops yet.
- Do not add launch-at-login yet.
- Do not add global keyboard shortcuts requiring Accessibility permission.
- Do not use native fullscreen Spaces.
- Do not add third-party dependencies.

Build/test:
- Ensure the project builds.
- Confirm Settings opens from Command + Shift + S.
- Confirm Settings opens from the menu bar item.
- Confirm the menu bar item only shows Settings and Quit.
- Confirm settings persist after app restart.
- Confirm the camera still works.
- Confirm fullscreen still works.
- Confirm Escape behavior follows the setting.
- Confirm the window still floats and resizes correctly.