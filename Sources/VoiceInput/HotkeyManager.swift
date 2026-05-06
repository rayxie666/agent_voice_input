import AppKit
import Carbon.HIToolbox

/// Registers two global hotkeys via Carbon's RegisterEventHotKey and dispatches
/// a callback when either fires. We re-register from scratch whenever the user
/// changes a binding.
final class HotkeyManager {
    enum Action { case raw, polish, polishLast }

    private struct Registration {
        let id: EventHotKeyID
        var ref: EventHotKeyRef?
        let action: Action
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?

    let onTrigger: (Action) -> Void

    init(onTrigger: @escaping (Action) -> Void) {
        self.onTrigger = onTrigger
        installHandler()
    }

    deinit {
        unregisterAll()
        if let h = handlerRef { RemoveEventHandler(h) }
    }

    func rebind(raw: KeyCombo, polish: KeyCombo, polishLast: KeyCombo) {
        unregisterAll()
        register(combo: raw, action: .raw)
        register(combo: polish, action: .polish)
        register(combo: polishLast, action: .polishLast)
    }

    // MARK: - Internals

    private func installHandler() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status != noErr { return status }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData)
                    .takeUnretainedValue()
                mgr.handle(id: hkID.id)
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
    }

    private func register(combo: KeyCombo, action: Action) {
        let id = nextID; nextID &+= 1
        let sig: OSType = 0x56494E50  // 'VINP'
        let hkID = EventHotKeyID(signature: sig, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.modifiers,
            hkID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref = ref {
            registrations[id] = Registration(id: hkID, ref: ref, action: action)
        } else {
            NSLog("VoiceInput: RegisterEventHotKey failed (status=\(status)) for \(combo.displayString)")
        }
    }

    private func unregisterAll() {
        for (_, reg) in registrations {
            if let ref = reg.ref { UnregisterEventHotKey(ref) }
        }
        registrations.removeAll()
    }

    private func handle(id: UInt32) {
        guard let reg = registrations[id] else { return }
        DispatchQueue.main.async { self.onTrigger(reg.action) }
    }
}
