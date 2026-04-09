//
//  HotkeyManager.swift
//  Foil 
//

import AppKit
import Carbon.HIToolbox

/// Global shortcut via Carbon `RegisterEventHotKey` (works with App Sandbox without Input Monitoring).
final class HotkeyManager {
    private static let signature: OSType = 0x504C5254 // 'PLRT'
    private static let hotKeyCallbackID: UInt32 = 1

    private static var installedHandler: EventHandlerRef?
    private static var mainFire: (() -> Void)?

    private static let hotKeyUPP: EventHandlerUPP = { _, event, _ -> OSStatus in
        guard let event else { return OSStatus(eventNotHandledErr) }
        var hk = EventHotKeyID()
        let err = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hk
        )
        if err != noErr { return err }
        if hk.signature == HotkeyManager.signature, hk.id == HotkeyManager.hotKeyCallbackID {
            DispatchQueue.main.async {
                HotkeyManager.mainFire?()
            }
        }
        return noErr
    }

    private var hotKeyRef: EventHotKeyRef?

    deinit {
        unregister()
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            FoilLog.hotkey("UnregisterEventHotKey")
        }
        Self.mainFire = nil
    }

    /// Registers the shortcut. Only one active registration is supported (last wins).
    func register(definition: HotkeyDefinition, onFire: @escaping () -> Void) {
        unregister()
        Self.mainFire = onFire

        if Self.installedHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            var handler: EventHandlerRef?
            let status = InstallEventHandler(GetApplicationEventTarget(), Self.hotKeyUPP, 1, &eventType, nil, &handler)
            if status == noErr {
                Self.installedHandler = handler
                FoilLog.hotkey("InstallEventHandler OK (keyboard hot key pressed)")
            } else {
                FoilLog.hotkey("InstallEventHandler failed: OSStatus \(status)")
            }
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyCallbackID)
        var ref: EventHotKeyRef?
        let reg = RegisterEventHotKey(
            definition.keyCode,
            definition.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(0),
            &ref
        )
        if reg == noErr {
            hotKeyRef = ref
            FoilLog.hotkey("RegisterEventHotKey OK: \(definition.displayString) (keyCode=\(definition.keyCode) mods=\(definition.carbonModifiers))")
        } else {
            FoilLog.hotkey("RegisterEventHotKey failed: OSStatus \(reg) for \(definition.displayString)")
        }
    }
}
