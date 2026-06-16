import AppKit
import SwiftUI

struct OverlayRootView: View {
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var cameraService: CameraService

    let onToggleFullscreen: () -> Void

    var body: some View {
        ZStack {
            CameraContentView(
                cameraService: cameraService,
                isMirrored: settingsStore.mirrorCamera,
                cropPercent: settingsStore.cropPercent,
                cropCenterX: settingsStore.cropCenterX,
                cropCenterY: settingsStore.cropCenterY
            )
            .modifier(WindowShapeModifier(
                settingsStore: settingsStore
            ))

            WindowPaneStroke(
                settingsStore: settingsStore
            )

            PaneInteractionOverlay(onDoubleClick: onToggleFullscreen)
        }
        .background(Color.clear)
        .onAppear {
            cameraService.start()
        }
        .onDisappear {
            cameraService.stop()
        }
    }

}

private struct WindowShapeModifier: ViewModifier {
    @ObservedObject var settingsStore: SettingsStore

    func body(content: Content) -> some View {
        switch settingsStore.windowShape {
        case .circle:
            content
                .clipShape(Circle())
        case .rounded:
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var cornerRadius: CGFloat {
        CGFloat(settingsStore.roundedCornerRadius)
    }
}

private struct WindowPaneStroke: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            switch settingsStore.windowShape {
            case .circle:
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)

                Circle()
                    .stroke(Color.black.opacity(0.35), lineWidth: 2)
                    .blur(radius: 0.5)
                    .offset(y: 1)
            case .rounded:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.35), lineWidth: 2)
                    .blur(radius: 0.5)
                    .offset(y: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private var cornerRadius: CGFloat {
        CGFloat(settingsStore.roundedCornerRadius)
    }
}

private struct CameraContentView: View {
    @ObservedObject var cameraService: CameraService
    let isMirrored: Bool
    let cropPercent: Double
    let cropCenterX: Double
    let cropCenterY: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.86)

            switch cameraService.state {
            case .checkingPermission:
                CameraPlaceholderView(
                    systemImage: "video.fill",
                    title: "Preparing Camera",
                    message: "Windowpane is checking camera access."
                )
            case .ready:
                GeometryReader { geometry in
                    CameraPreviewView(
                        session: cameraService.session,
                        isMirrored: isMirrored
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(
                        CGSize(
                            width: CGFloat(cropScale),
                            height: CGFloat(cropScale)
                        ),
                        anchor: .center
                    )
                    .offset(
                        x: CGFloat(safeCropCenterX) * (geometry.size.width * CGFloat(cropScale - 1) / 2),
                        y: CGFloat(safeCropCenterY) * (geometry.size.height * CGFloat(cropScale - 1) / 2)
                    )
                }
            case .permissionDenied:
                CameraPlaceholderView(
                    systemImage: "video.slash.fill",
                    title: "Camera Permission Needed",
                    message: "Allow camera access in System Settings to show your live camera pane."
                )
            case .cameraUnavailable:
                CameraPlaceholderView(
                    systemImage: "video.slash.fill",
                    title: "No Camera Found",
                    message: "Connect a camera to show your live camera pane."
                )
            case .configurationFailed(let message):
                CameraPlaceholderView(
                    systemImage: "exclamationmark.triangle.fill",
                    title: "Camera Unavailable",
                    message: message
                )
            }
        }
    }

    private var cropScale: Double {
        max(1, 100 / max(25, cropPercent))
    }

    private var safeCropCenterX: Double {
        max(-1, min(1, cropCenterX))
    }

    private var safeCropCenterY: Double {
        max(-1, min(1, cropCenterY))
    }
}

private struct PaneInteractionOverlay: NSViewRepresentable {
    let onDoubleClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> PaneInteractionView {
        let view = PaneInteractionView()
        let recognizer = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        recognizer.numberOfClicksRequired = 2
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateNSView(_ nsView: PaneInteractionView, context: Context) {
        context.coordinator.onDoubleClick = onDoubleClick
    }

    final class Coordinator: NSObject {
        var onDoubleClick: () -> Void

        init(onDoubleClick: @escaping () -> Void) {
            self.onDoubleClick = onDoubleClick
        }

        @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended else {
                return
            }

            onDoubleClick()
        }
    }
}

private final class PaneInteractionView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

private struct CameraPlaceholderView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))

            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white)
        .padding(32)
    }
}
