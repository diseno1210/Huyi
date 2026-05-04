import AppKit
import Carbon

struct GlobalHotKey {
    let id: UInt32
    let keyCode: UInt32
    let modifiers: UInt32
    let handler: () -> Void
}

final class HotKeyController {
    private let hotKeys: [GlobalHotKey]
    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    init(hotKeys: [GlobalHotKey]) {
        self.hotKeys = hotKeys
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        handlers = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.id, $0.handler) })

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                controller.handlers[hotKeyID.id]?()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        for hotKey in hotKeys {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: "LST1".fourCharCode, id: hotKey.id)
            RegisterEventHotKey(
                hotKey.keyCode,
                hotKey.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
            }
        }
    }
}

private extension String {
    var fourCharCode: OSType {
        var result: OSType = 0
        for scalar in unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }
}
