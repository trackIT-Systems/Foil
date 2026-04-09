//
//  HotkeyRecorder.swift
//  Foil
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

extension NSEvent.ModifierFlags {
    /// Carbon modifier mask for `RegisterEventHotKey` (same masks as `HotkeyDefinition.displayString`).
    fileprivate var foilCarbonModifiers: UInt32 {
        var carbon: UInt32 = 0
        let mask = intersection(.deviceIndependentFlagsMask)
        if mask.contains(.control) { carbon |= UInt32(controlKey) }
        if mask.contains(.option) { carbon |= UInt32(optionKey) }
        if mask.contains(.shift) { carbon |= UInt32(shiftKey) }
        if mask.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }
}

final class HotkeyCaptureNSView: NSView {
    var onCapture: ((HotkeyDefinition) -> Void)?
    var onCancel: (() -> Void)?
    var onPreview: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    private func emitPreview(_ string: String) {
        DispatchQueue.main.async { [onPreview] in
            onPreview?(string)
        }
    }

    private func updatePreviewFromCurrentModifiers() {
        let carbon = NSEvent.modifierFlags.foilCarbonModifiers
        let prefix = HotkeyDefinition.modifierDisplayPrefix(carbonModifiers: carbon)
        emitPreview(prefix.isEmpty ? "" : prefix + "…")
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            updatePreviewFromCurrentModifiers()
        }
        return ok
    }

    override func flagsChanged(with event: NSEvent) {
        guard window?.firstResponder === self else { return }
        let carbon = event.modifierFlags.foilCarbonModifiers
        let prefix = HotkeyDefinition.modifierDisplayPrefix(carbonModifiers: carbon)
        emitPreview(prefix.isEmpty ? "" : prefix + "…")
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }

        let deviceMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == UInt16(kVK_Escape), deviceMods.isEmpty {
            emitPreview("")
            onCancel?()
            return
        }

        let carbonMods = event.modifierFlags.foilCarbonModifiers
        guard carbonMods != 0 else {
            NSSound.beep()
            return
        }

        let definition = HotkeyDefinition(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
        emitPreview(definition.displayString)
        onCapture?(definition)
    }
}

struct HotkeyRecorderKeyView: NSViewRepresentable {
    var isActive: Bool
    let onPreview: (String) -> Void
    let onCapture: (HotkeyDefinition) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotkeyCaptureNSView {
        let view = HotkeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.onPreview = onPreview
        return view
    }

    func updateNSView(_ nsView: HotkeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.onPreview = onPreview
        let shouldFocus = isActive
        guard shouldFocus else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.makeFirstResponder(nsView)
        }
    }
}
