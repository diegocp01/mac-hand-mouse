import Carbon

/// Registers only the selected shortcut; no global keystroke stream is collected.
final class ResumeShortcut {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x484D5253 // HMRS

    init() {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<ResumeShortcut>.fromOpaque(context).takeUnretainedValue()
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                id.signature == shortcut.signature, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { shortcut.onPress?() }
            else { shortcut.onRelease?() }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// 0 = Control-Option-Command-H, 1 = Control-Option-Command-M, 2 = disabled.
    func configure(_ choice: Int) -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard choice != 2 else { return true }
        guard handler != nil, choice == 0 || choice == 1 else { return false }
        let key = choice == 0 ? kVK_ANSI_H : kVK_ANSI_M
        return RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
