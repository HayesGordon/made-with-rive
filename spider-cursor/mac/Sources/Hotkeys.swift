import Carbon

/// Ctrl-option 0 to 5 for the agent modes, and H for home, system-wide. Carbon hot keys need no Accessibility
/// permission, and the keystroke goes to this app instead of the one in
/// front, so nothing gets typed into it.
final class Hotkeys {
    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private let onDigit: (Int) -> Void
    private let onHome: () -> Void
    /// The hot key id for H; the digits use their own value.
    private static let homeID: UInt32 = 100

    init(onDigit: @escaping (Int) -> Void, onHome: @escaping () -> Void) {
        self.onDigit = onDigit
        self.onHome = onHome
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let keys = Unmanaged<Hotkeys>.fromOpaque(context!).takeUnretainedValue()
            if id.id == Hotkeys.homeID {
                keys.onHome()
            } else {
                keys.onDigit(Int(id.id))
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let codes = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5]
        for (digit, code) in codes.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(code), UInt32(controlKey | optionKey),
                                EventHotKeyID(signature: OSType(0x5350_4452), id: UInt32(digit)),
                                GetApplicationEventTarget(), 0, &ref)
            refs.append(ref)
        }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x5350_4452), id: Hotkeys.homeID),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}
