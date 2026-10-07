import Carbon.HIToolbox

/// Carbon 전역 단축키 (⌃⌥Space). 접근성 권한이 필요 없다.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    var isRegistered: Bool { ref != nil }

    func register() {
        guard ref == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, ctx in
            let me = Unmanaged<GlobalHotKey>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
                            EventHotKeyID(signature: OSType(0x41544D48), id: 1),  // 'ATMH'
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil; handler = nil
    }

    deinit { unregister() }
}
