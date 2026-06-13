Implement custom resize handles for a borderless floating macOS overlay window.

Current app:
- SwiftUI/AppKit hybrid macOS app named Windowpane
- AppDelegate creates WindowController
- WindowController creates OverlayWindow
- OverlayRootView is hosted inside NSHostingView
- Window is floating above normal apps
- Window should have no visible traffic lights or titlebar chrome

Goal:
Make the borderless overlay window resizable from all edges and corners.

Requirements:
1. Keep the window visually borderless/chromeless.
2. Keep the rounded SwiftUI content.
3. Add invisible resize hit zones on:
   - top
   - bottom
   - left
   - right
   - top-left
   - top-right
   - bottom-left
   - bottom-right
4. Dragging the interior background should move the window.
5. Dragging an edge/corner should resize the window.
6. Enforce min size 260x160.
7. Use AppKit mouse tracking / NSView hit zones if needed.
8. Do not use private APIs.
9. Do not use native fullscreen spaces.
10. Keep WindowController responsible for window-level behavior.
11. Return full modified files.