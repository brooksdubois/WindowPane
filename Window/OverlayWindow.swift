import AppKit

final class OverlayWindow: NSWindow {
    var onToggleOverlayFullscreen: (() -> Void)?
    var onExitOverlayFullscreen: (() -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        if handlesKeyDown(event) {
            return
        }

        super.sendEvent(event)
    }

    private func handlesKeyDown(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            return onExitOverlayFullscreen?() ?? false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard modifiers == [.option, .shift], event.charactersIgnoringModifiers?.lowercased() == "f" else {
            return false
        }

        onToggleOverlayFullscreen?()
        return true
    }
}
