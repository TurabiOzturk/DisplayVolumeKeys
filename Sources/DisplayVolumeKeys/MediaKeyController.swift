import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

final class MediaKeyController {
    private let logger = Logger(subsystem: "com.turabiozturk.DisplayVolumeKeys", category: "MediaKeys")
    enum Key {
        case volumeUp
        case volumeDown
        case mute
    }

    var onKey: ((Key) -> Void)?
    var shouldIntercept: () -> Bool = { false }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func start() -> Bool {
        if eventTap != nil { return true }
        guard hasAccessibilityPermission else {
            logger.notice("Waiting for Accessibility permission")
            return false
        }

        let mask = CGEventMask(1) << UInt32(NX_SYSDEFINED)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyEventCallback,
            userInfo: pointer
        )

        guard let eventTap else {
            logger.error("Could not create media-key event tap")
            return false
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        logger.info("Media-key event tap started")
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopSourceInvalidate(runLoopSource)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let flags = Int32(data & 0x0000_FFFF)
        let isKeyDown = ((flags & 0xFF00) >> 8) == 0xA
        let isRepeat = (flags & 0x1) == 0x1

        let key: Key
        switch keyCode {
        case NX_KEYTYPE_SOUND_UP: key = .volumeUp
        case NX_KEYTYPE_SOUND_DOWN: key = .volumeDown
        case NX_KEYTYPE_MUTE: key = .mute
        default: return Unmanaged.passUnretained(event)
        }

        guard shouldIntercept() else { return Unmanaged.passUnretained(event) }
        if isKeyDown, !(key == .mute && isRepeat) {
            logger.info("Captured monitor volume media key")
            onKey?(key)
        }
        return nil
    }

    deinit {
        stop()
    }
}

private func mediaKeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<MediaKeyController>.fromOpaque(userInfo).takeUnretainedValue()
    return controller.handle(type: type, event: event)
}
