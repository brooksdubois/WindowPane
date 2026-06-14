import AppKit
import SwiftUI

final class WindowController: NSWindowController {
    private enum Metrics {
        static let minimumWindowSize = NSSize(width: 260, height: 160)
        static let cornerRadius: CGFloat = 28
    }

    private enum OverlayWindowState {
        static let level: NSWindow.Level = .statusBar
        static let collectionBehavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]
    }

    private var savedNormalFrame: NSRect?
    private var savedNormalWindowLevel: NSWindow.Level?
    private var isOverlayFullscreen = false

    convenience init() {
        let hostingView = NSHostingView(rootView: OverlayRootView(
            cornerRadius: Metrics.cornerRadius,
            onToggleFullscreen: {}
        ))
        let contentView = ResizableOverlayContentView(
            contentView: hostingView,
            cornerRadius: Metrics.cornerRadius
        )

        let window = OverlayWindow(
            contentRect: NSRect(x: 200, y: 200, width: 420, height: 300),
            styleMask: [
                .borderless,
                .resizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "Windowpane"
        window.contentView = contentView
        window.isReleasedWhenClosed = false

        window.level = OverlayWindowState.level
        window.collectionBehavior = OverlayWindowState.collectionBehavior

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        window.isMovableByWindowBackground = true
        window.minSize = Metrics.minimumWindowSize

        self.init(window: window)

        hostingView.rootView = OverlayRootView(
            cornerRadius: Metrics.cornerRadius,
            onToggleFullscreen: { [weak self] in
                self?.toggleOverlayFullscreen()
            }
        )
        window.onToggleOverlayFullscreen = { [weak self] in
            self?.toggleOverlayFullscreen()
        }
        window.onExitOverlayFullscreen = { [weak self] in
            self?.exitOverlayFullscreen() ?? false
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        restoreFloatingOverlayBehavior(level: isOverlayFullscreen ? .screenSaver : OverlayWindowState.level)
        window?.orderFrontRegardless()
    }

    private func toggleOverlayFullscreen() {
        if isOverlayFullscreen {
            exitOverlayFullscreen()
        } else {
            enterOverlayFullscreen()
        }
    }

    private func enterOverlayFullscreen() {
        guard let window, !isOverlayFullscreen else {
            return
        }

        savedNormalFrame = window.frame
        savedNormalWindowLevel = window.level
        isOverlayFullscreen = true

        restoreFloatingOverlayBehavior(level: .screenSaver)
        window.hasShadow = false
        window.setFrame(targetFullscreenFrame(for: window), display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @discardableResult
    private func exitOverlayFullscreen() -> Bool {
        guard let window, isOverlayFullscreen else {
            return false
        }

        let frameToRestore = savedNormalFrame
        let levelToRestore = savedNormalWindowLevel ?? OverlayWindowState.level
        savedNormalFrame = nil
        savedNormalWindowLevel = nil
        isOverlayFullscreen = false

        restoreFloatingOverlayBehavior(level: levelToRestore)
        window.hasShadow = true

        if let frameToRestore {
            window.setFrame(frameToRestore, display: true, animate: false)
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        return true
    }

    private func restoreFloatingOverlayBehavior(level: NSWindow.Level = OverlayWindowState.level) {
        guard let window else {
            return
        }

        window.level = level
        window.collectionBehavior = OverlayWindowState.collectionBehavior
        window.isMovableByWindowBackground = true
        window.minSize = Metrics.minimumWindowSize
    }

    private func targetFullscreenFrame(for window: NSWindow) -> NSRect {
        if let screen = window.screen {
            return screen.frame
        }

        let windowFrame = window.frame
        let screenContainingWindow = NSScreen.screens.max { first, second in
            first.frame.intersection(windowFrame).area < second.frame.intersection(windowFrame).area
        }

        return screenContainingWindow?.frame ?? NSScreen.main?.frame ?? windowFrame
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull else {
            return 0
        }

        return width * height
    }
}

private final class ResizableOverlayContentView: NSView {
    private enum Metrics {
        static let edgeThickness: CGFloat = 12
    }

    private let contentView: NSView
    private let cornerRadius: CGFloat
    private let topHandle = ResizeHandleView(edges: [.top])
    private let bottomHandle = ResizeHandleView(edges: [.bottom])
    private let leftHandle = ResizeHandleView(edges: [.left])
    private let rightHandle = ResizeHandleView(edges: [.right])
    private let topLeftHandle = ResizeHandleView(edges: [.top, .left])
    private let topRightHandle = ResizeHandleView(edges: [.top, .right])
    private let bottomLeftHandle = ResizeHandleView(edges: [.bottom, .left])
    private let bottomRightHandle = ResizeHandleView(edges: [.bottom, .right])

    init(contentView: NSView, cornerRadius: CGFloat) {
        self.contentView = contentView
        self.cornerRadius = cornerRadius

        super.init(frame: .zero)

        wantsLayer = false
        addSubview(contentView)

        [
            topHandle,
            bottomHandle,
            leftHandle,
            rightHandle,
            topLeftHandle,
            topRightHandle,
            bottomLeftHandle,
            bottomRightHandle
        ].forEach { handle in
            addSubview(handle)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        false
    }

    override func layout() {
        super.layout()

        contentView.frame = bounds

        let width = bounds.width
        let height = bounds.height
        let edgeThickness = Metrics.edgeThickness
        let cornerLength = min(cornerRadius, width / 2, height / 2)
        let horizontalEdgeWidth = max(0, width - (cornerLength * 2))
        let verticalEdgeHeight = max(0, height - (cornerLength * 2))

        topLeftHandle.frame = NSRect(
            x: 0,
            y: height - cornerLength,
            width: cornerLength,
            height: cornerLength
        )
        topRightHandle.frame = NSRect(
            x: width - cornerLength,
            y: height - cornerLength,
            width: cornerLength,
            height: cornerLength
        )
        bottomLeftHandle.frame = NSRect(
            x: 0,
            y: 0,
            width: cornerLength,
            height: cornerLength
        )
        bottomRightHandle.frame = NSRect(
            x: width - cornerLength,
            y: 0,
            width: cornerLength,
            height: cornerLength
        )

        topHandle.frame = NSRect(
            x: cornerLength,
            y: height - edgeThickness,
            width: horizontalEdgeWidth,
            height: edgeThickness
        )
        bottomHandle.frame = NSRect(
            x: cornerLength,
            y: 0,
            width: horizontalEdgeWidth,
            height: edgeThickness
        )
        leftHandle.frame = NSRect(
            x: 0,
            y: cornerLength,
            width: edgeThickness,
            height: verticalEdgeHeight
        )
        rightHandle.frame = NSRect(
            x: width - edgeThickness,
            y: cornerLength,
            width: edgeThickness,
            height: verticalEdgeHeight
        )
    }
}

private struct ResizeEdges: OptionSet {
    let rawValue: Int

    static let top = ResizeEdges(rawValue: 1 << 0)
    static let bottom = ResizeEdges(rawValue: 1 << 1)
    static let left = ResizeEdges(rawValue: 1 << 2)
    static let right = ResizeEdges(rawValue: 1 << 3)
}

private final class ResizeHandleView: NSView {
    private let edges: ResizeEdges
    private var initialWindowFrame: NSRect = .zero
    private var initialMouseLocation: NSPoint = .zero

    init(edges: ResizeEdges) {
        self.edges = edges

        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        initialWindowFrame = window.frame
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - initialMouseLocation.x
        let deltaY = currentMouseLocation.y - initialMouseLocation.y
        let minSize = window.minSize
        var newFrame = initialWindowFrame

        if edges.contains(.left) {
            newFrame.origin.x = initialWindowFrame.origin.x + deltaX
            newFrame.size.width = initialWindowFrame.size.width - deltaX

            if newFrame.size.width < minSize.width {
                newFrame.size.width = minSize.width
                newFrame.origin.x = initialWindowFrame.maxX - minSize.width
            }
        }

        if edges.contains(.right) {
            newFrame.size.width = max(minSize.width, initialWindowFrame.size.width + deltaX)
        }

        if edges.contains(.bottom) {
            newFrame.origin.y = initialWindowFrame.origin.y + deltaY
            newFrame.size.height = initialWindowFrame.size.height - deltaY

            if newFrame.size.height < minSize.height {
                newFrame.size.height = minSize.height
                newFrame.origin.y = initialWindowFrame.maxY - minSize.height
            }
        }

        if edges.contains(.top) {
            newFrame.size.height = max(minSize.height, initialWindowFrame.size.height + deltaY)
        }

        window.setFrame(newFrame, display: true)
    }

    private var cursor: NSCursor {
        switch (edges.contains(.left) || edges.contains(.right), edges.contains(.top) || edges.contains(.bottom)) {
        case (true, true):
            return NSCursor.frameResize(position: cursorPosition, directions: .all)
        case (true, false):
            return .resizeLeftRight
        case (false, true):
            return .resizeUpDown
        case (false, false):
            return .arrow
        }
    }

    private var cursorPosition: NSCursor.FrameResizePosition {
        switch (edges.contains(.top), edges.contains(.bottom), edges.contains(.left), edges.contains(.right)) {
        case (true, false, true, false):
            return .topLeft
        case (true, false, false, true):
            return .topRight
        case (false, true, true, false):
            return .bottomLeft
        case (false, true, false, true):
            return .bottomRight
        case (true, false, false, false):
            return .top
        case (false, true, false, false):
            return .bottom
        case (false, false, true, false):
            return .left
        case (false, false, false, true):
            return .right
        default:
            return .topLeft
        }
    }
}
