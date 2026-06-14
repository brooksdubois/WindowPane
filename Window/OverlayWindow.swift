import AppKit

final class OverlayWindow: NSWindow {
    var onToggleOverlayFullscreen: (() -> Void)?
    var onExitOverlayFullscreen: (() -> Bool)?
    var onOpenSettings: (() -> Void)?
    var fullscreenShortcut: FullscreenKeyboardShortcut = .optionShiftF

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
        if isSettingsShortcut(event) {
            onOpenSettings?()
            return true
        }

        if event.keyCode == 53 {
            return onExitOverlayFullscreen?() ?? false
        }

        guard fullscreenShortcut.matches(event) else {
            return false
        }

        onToggleOverlayFullscreen?()
        return true
    }

    private func isSettingsShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers == [.command, .shift]
            && event.charactersIgnoringModifiers?.lowercased() == "s"
    }
}
