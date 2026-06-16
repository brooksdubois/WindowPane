import AppKit
import Combine
import SwiftUI

final class WindowController: NSWindowController {
    private enum Metrics {
        static let defaultFrame = NSRect(x: 200, y: 200, width: 420, height: 300)
        static let minimumWindowSize = NSSize(width: 260, height: 160)
    }

    private enum OverlayWindowState {
        static let level: NSWindow.Level = .statusBar
        static let baseCollectionBehavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
    }

    private let settingsStore: SettingsStore
    private let cameraService: CameraService
    private let resizableContentView: ResizableOverlayContentView
    private let onOpenSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private var savedNormalFrame: NSRect?
    private var savedNormalWindowLevel: NSWindow.Level?
    private var isOverlayFullscreen = false

    init(
        settingsStore: SettingsStore,
        cameraService: CameraService,
        onOpenSettings: @escaping () -> Void
    ) {
        self.settingsStore = settingsStore
        self.cameraService = cameraService
        self.onOpenSettings = onOpenSettings

        let initialCornerRadius = CGFloat(settingsStore.roundedCornerRadius)
        let initialWindowShape = settingsStore.windowShape
        let hostingView = NSHostingView(rootView: OverlayRootView(
            settingsStore: settingsStore,
            cameraService: cameraService,
            onToggleFullscreen: {}
        ))
        let contentView = ResizableOverlayContentView(
            contentView: hostingView,
            cornerRadius: initialCornerRadius,
            windowShape: initialWindowShape
        )
        self.resizableContentView = contentView

        let window = OverlayWindow(
            contentRect: settingsStore.restoredWindowFrame(defaultFrame: Metrics.defaultFrame),
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
        window.collectionBehavior = Self.collectionBehavior(showOnAllSpaces: settingsStore.showOnAllSpaces)

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = settingsStore.windowShadow

        window.isMovableByWindowBackground = true
        window.minSize = Metrics.minimumWindowSize

        super.init(window: window)

        hostingView.rootView = OverlayRootView(
            settingsStore: settingsStore,
            cameraService: cameraService,
            onToggleFullscreen: { [weak self] in
                self?.toggleOverlayFullscreen()
            }
        )
        window.onToggleOverlayFullscreen = { [weak self] in
            self?.toggleOverlayFullscreen()
        }
        window.onExitOverlayFullscreen = { [weak self] in
            guard self?.settingsStore.escapeExitsFullscreen == true else {
                return false
            }

            return self?.exitOverlayFullscreen() ?? false
        }
        window.onOpenSettings = { [weak self] in
            self?.onOpenSettings()
        }
        window.fullscreenShortcut = settingsStore.fullscreenShortcut
        window.delegate = self

        observeSettings()
        applyWindowSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)

        restoreFloatingOverlayBehavior(level: isOverlayFullscreen ? .screenSaver : OverlayWindowState.level)
        window?.orderFrontRegardless()
    }

    private func observeSettings() {
        settingsStore.$showOnAllSpaces
            .sink { [weak self] _ in
                self?.applyWindowSettings()
            }
            .store(in: &cancellables)

        settingsStore.$windowShadow
            .sink { [weak self] _ in
                self?.applyWindowSettings()
            }
            .store(in: &cancellables)

        settingsStore.$roundedCornerRadius
            .sink { [weak self] cornerRadius in
                self?.resizableContentView.cornerRadius = CGFloat(cornerRadius)
            }
            .store(in: &cancellables)

        settingsStore.$windowShape
            .sink { [weak self] windowShape in
                self?.resizableContentView.windowShape = windowShape
            }
            .store(in: &cancellables)

        settingsStore.$fullscreenShortcut
            .sink { [weak self] shortcut in
                (self?.window as? OverlayWindow)?.fullscreenShortcut = shortcut
            }
            .store(in: &cancellables)

        settingsStore.$rememberWindowPosition
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveWindowFrameIfNeeded()
            }
            .store(in: &cancellables)

        settingsStore.$rememberWindowSize
            .dropFirst()
            .sink { [weak self] _ in
                self?.saveWindowFrameIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func applyWindowSettings() {
        guard let window else {
            return
        }

        window.collectionBehavior = Self.collectionBehavior(showOnAllSpaces: settingsStore.showOnAllSpaces)

        if !isOverlayFullscreen {
            window.level = OverlayWindowState.level
            window.hasShadow = settingsStore.windowShadow
        }

        window.isMovableByWindowBackground = true
        window.minSize = Metrics.minimumWindowSize
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
        window.hasShadow = settingsStore.windowShadow

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
        window.collectionBehavior = Self.collectionBehavior(showOnAllSpaces: settingsStore.showOnAllSpaces)
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

    private func saveWindowFrameIfNeeded() {
        guard let window, !isOverlayFullscreen else {
            return
        }

        settingsStore.saveWindowFrame(window.frame)
    }

    private static func collectionBehavior(showOnAllSpaces: Bool) -> NSWindow.CollectionBehavior {
        var behavior = OverlayWindowState.baseCollectionBehavior

        if showOnAllSpaces {
            behavior.insert(.canJoinAllSpaces)
        }

        return behavior
    }
}

extension WindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        saveWindowFrameIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        saveWindowFrameIfNeeded()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowFrameIfNeeded()
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
    var cornerRadius: CGFloat {
        didSet {
            needsLayout = true
        }
    }
    var windowShape: WindowShape {
        didSet {
            needsLayout = true
        }
    }
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
        self.windowShape = .rounded

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

    convenience init(
        contentView: NSView,
        cornerRadius: CGFloat,
        windowShape: WindowShape
    ) {
        self.init(contentView: contentView, cornerRadius: cornerRadius)
        self.windowShape = windowShape

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
            handle.resizeCalculator = { [weak self] initialFrame, edges, deltaX, deltaY, minSize in
                self?.nextFrame(
                    from: initialFrame,
                    edges: edges,
                    deltaX: deltaX,
                    deltaY: deltaY,
                    minSize: minSize
                ) ?? initialFrame
            }
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

        let edgeThickness = Metrics.edgeThickness
        let geometry = handleGeometry(for: bounds, edgeThickness: edgeThickness)

        topLeftHandle.frame = geometry.topLeft
        topRightHandle.frame = geometry.topRight
        bottomLeftHandle.frame = geometry.bottomLeft
        bottomRightHandle.frame = geometry.bottomRight

        topHandle.frame = geometry.top
        bottomHandle.frame = geometry.bottom
        leftHandle.frame = geometry.left
        rightHandle.frame = geometry.right
    }

    private func handleGeometry(for bounds: NSRect, edgeThickness: CGFloat) -> HandleGeometry {
        switch windowShape {
        case .rounded:
            let cornerLength = min(cornerRadius, bounds.width / 2, bounds.height / 2)
            let horizontalEdgeWidth = max(0, bounds.width - (cornerLength * 2))
            let verticalEdgeHeight = max(0, bounds.height - (cornerLength * 2))

            return HandleGeometry(
                topLeft: NSRect(
                    x: 0,
                    y: bounds.height - cornerLength,
                    width: cornerLength,
                    height: cornerLength
                ),
                topRight: NSRect(
                    x: bounds.width - cornerLength,
                    y: bounds.height - cornerLength,
                    width: cornerLength,
                    height: cornerLength
                ),
                bottomLeft: NSRect(
                    x: 0,
                    y: 0,
                    width: cornerLength,
                    height: cornerLength
                ),
                bottomRight: NSRect(
                    x: bounds.width - cornerLength,
                    y: 0,
                    width: cornerLength,
                    height: cornerLength
                ),
                top: NSRect(
                    x: cornerLength,
                    y: bounds.height - edgeThickness,
                    width: horizontalEdgeWidth,
                    height: edgeThickness
                ),
                bottom: NSRect(
                    x: cornerLength,
                    y: 0,
                    width: horizontalEdgeWidth,
                    height: edgeThickness
                ),
                left: NSRect(
                    x: 0,
                    y: cornerLength,
                    width: edgeThickness,
                    height: verticalEdgeHeight
                ),
                right: NSRect(
                    x: bounds.width - edgeThickness,
                    y: cornerLength,
                    width: edgeThickness,
                    height: verticalEdgeHeight
                )
            )

        case .circle:
            let diameter = min(bounds.width, bounds.height)
            let circleInsetX = max(0, (bounds.width - diameter) / 2)
            let circleInsetY = max(0, (bounds.height - diameter) / 2)
            let circleRect = NSRect(
                x: circleInsetX,
                y: circleInsetY,
                width: diameter,
                height: diameter
            )
            let cornerLength = min(40, max(12, diameter / 6))
            let circleCenter = CGPoint(
                x: circleRect.midX,
                y: circleRect.midY
            )
            let diagonalOffset = (diameter / 2) / sqrt(2)

            return HandleGeometry(
                topLeft: NSRect(
                    x: circleCenter.x - diagonalOffset - (cornerLength / 2),
                    y: circleCenter.y + diagonalOffset - (cornerLength / 2),
                    width: cornerLength,
                    height: cornerLength
                ),
                topRight: NSRect(
                    x: circleCenter.x + diagonalOffset - (cornerLength / 2),
                    y: circleCenter.y + diagonalOffset - (cornerLength / 2),
                    width: cornerLength,
                    height: cornerLength
                ),
                bottomLeft: NSRect(
                    x: circleCenter.x - diagonalOffset - (cornerLength / 2),
                    y: circleCenter.y - diagonalOffset - (cornerLength / 2),
                    width: cornerLength,
                    height: cornerLength
                ),
                bottomRight: NSRect(
                    x: circleCenter.x + diagonalOffset - (cornerLength / 2),
                    y: circleCenter.y - diagonalOffset - (cornerLength / 2),
                    width: cornerLength,
                    height: cornerLength
                ),
                top: NSRect(
                    x: circleRect.minX,
                    y: circleRect.maxY - edgeThickness,
                    width: circleRect.width,
                    height: edgeThickness
                ),
                bottom: NSRect(
                    x: circleRect.minX,
                    y: circleRect.minY,
                    width: circleRect.width,
                    height: edgeThickness
                ),
                left: NSRect(
                    x: circleRect.minX,
                    y: circleRect.minY,
                    width: edgeThickness,
                    height: circleRect.height
                ),
                right: NSRect(
                    x: circleRect.maxX - edgeThickness,
                    y: circleRect.minY,
                    width: edgeThickness,
                    height: circleRect.height
                )
            )
        }
    }

    private func nextFrame(
        from initialWindowFrame: NSRect,
        edges: ResizeEdges,
        deltaX: CGFloat,
        deltaY: CGFloat,
        minSize: NSSize
    ) -> NSRect {
        switch windowShape {
        case .rounded:
            return roundedNextFrame(
                from: initialWindowFrame,
                edges: edges,
                deltaX: deltaX,
                deltaY: deltaY,
                minSize: minSize
            )
        case .circle:
            return circularNextFrame(
                from: initialWindowFrame,
                edges: edges,
                deltaX: deltaX,
                deltaY: deltaY,
                minSize: minSize
            )
        }
    }

    private func roundedNextFrame(
        from initialWindowFrame: NSRect,
        edges: ResizeEdges,
        deltaX: CGFloat,
        deltaY: CGFloat,
        minSize: NSSize
    ) -> NSRect {
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

        return newFrame
    }

    private func circularNextFrame(
        from initialWindowFrame: NSRect,
        edges: ResizeEdges,
        deltaX: CGFloat,
        deltaY: CGFloat,
        minSize: NSSize
    ) -> NSRect {
        let minSquareSize = max(minSize.width, minSize.height)
        let candidateDeltas: [CGFloat] = [
            edges.contains(.left) ? -deltaX : 0,
            edges.contains(.right) ? deltaX : 0,
            edges.contains(.bottom) ? -deltaY : 0,
            edges.contains(.top) ? deltaY : 0
        ].filter { $0 != 0 }

        guard let delta = candidateDeltas.max(by: { abs($0) < abs($1) }) else {
            return initialWindowFrame
        }

        let currentSide = min(initialWindowFrame.width, initialWindowFrame.height)
        let requestedSide = max(minSquareSize, currentSide + delta)

        if requestedSide == currentSide {
            return initialWindowFrame
        }

        var nextOrigin = initialWindowFrame.origin
        var nextFrame = NSRect(
            x: nextOrigin.x,
            y: nextOrigin.y,
            width: requestedSide,
            height: requestedSide
        )

        if edges.contains(.left) {
            nextOrigin.x += currentSide - requestedSide
        }

        if edges.contains(.bottom) {
            nextOrigin.y += currentSide - requestedSide
        }

        nextFrame.origin = nextOrigin
        return nextFrame
    }
}

private struct HandleGeometry {
    let topLeft: NSRect
    let topRight: NSRect
    let bottomLeft: NSRect
    let bottomRight: NSRect
    let top: NSRect
    let bottom: NSRect
    let left: NSRect
    let right: NSRect
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
    var resizeCalculator: (NSRect, ResizeEdges, CGFloat, CGFloat, NSSize) -> NSRect = { initialFrame, _edges, _deltaX, _deltaY, minSize in
        return NSRect(
            origin: initialFrame.origin,
            size: NSSize(
                width: max(minSize.width, initialFrame.size.width),
                height: max(minSize.height, initialFrame.size.height)
            )
        )
    }
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
        let nextFrame = resizeCalculator(initialWindowFrame, edges, deltaX, deltaY, minSize)

        window.setFrame(nextFrame, display: true)
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
