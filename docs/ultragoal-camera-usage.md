We have a native macOS SwiftUI + AppKit project called Windowpane.

The app currently uses:
- WindowpaneApp.swift with @NSApplicationDelegateAdaptor(AppDelegate.self)
- AppDelegate creates a WindowController
- WindowController creates a custom OverlayWindow with a SwiftUI OverlayRootView
- The window is floating, resizable, transparent-capable, and movable by background
- App Sandbox is enabled
- Camera entitlement is enabled
- NSCameraUsageDescription is already configured

Goal:
Implement a live camera preview inside the existing overlay window.

Requirements:
1. Use AVFoundation.
2. Request camera permission cleanly on launch or before starting capture.
3. If permission is denied, show a friendly placeholder view explaining that camera permission is required.
4. Use AVCaptureSession with the default video camera.
5. Render the camera preview using AVCaptureVideoPreviewLayer wrapped in NSViewRepresentable.
6. Preserve the existing AppKit window architecture.
7. Do not replace WindowController, OverlayWindow, or AppDelegate unless absolutely necessary.
8. The camera preview should fill the rounded rectangle area.
9. The preview should use aspect fill, not aspect fit.
10. Mirror the preview horizontally because this is a self-view camera pane.
11. Keep the UI minimal: no controls yet, just the live camera.
12. Make sure session start/stop does not block the main thread.
13. Use a small camera service/object if useful, but keep the implementation straightforward.
14. Do not add microphone capture.
15. Do not add screen recording capture.
16. Do not add third-party dependencies.

Expected files:
- CameraPreviewView.swift
- CameraPermissionService.swift if needed
- Updates to OverlayRootView.swift
- Minor supporting model/view-model code if needed

Return the full modified files, not patches.