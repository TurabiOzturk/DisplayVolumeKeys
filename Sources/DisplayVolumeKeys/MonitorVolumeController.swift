import AppleSiliconDDC
import Foundation
import OSLog

struct MonitorVolumeStatus {
    let available: Bool
    let monitorName: String?
    let level: Float?
    let muted: Bool
    let message: String
}

final class MonitorVolumeController {
    private let logger = Logger(subsystem: "com.turabiozturk.DisplayVolumeKeys", category: "DDC")

    private enum VCP {
        static let volume: UInt8 = 0x62
        static let mute: UInt8 = 0x8D
    }

    private struct Target {
        let display: AppleSiliconDDC.IOregService
        var currentVolume: UInt16
        let maximumVolume: UInt16
        var isMuted: Bool
        let supportsMute: Bool
        var lastNonZeroVolume: UInt16
    }

    var onStatusChange: ((MonitorVolumeStatus) -> Void)?
    var onOSD: ((_ level: Float, _ muted: Bool, _ monitorName: String) -> Void)?

    private let queue = DispatchQueue(label: "com.turabiozturk.DisplayVolumeKeys.ddc")
    private var target: Target?

    func start() {
        refresh()
    }

    func refresh() {
        publish(MonitorVolumeStatus(
            available: false,
            monitorName: nil,
            level: nil,
            muted: false,
            message: "Searching for a DDC volume control…"
        ))
        queue.async { [weak self] in
            self?.target = nil
            self?.discoverTarget()
        }
    }

    func handle(_ key: MediaKeyController.Key) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.target == nil { self.discoverTarget() }
            guard self.target != nil else { return }

            switch key {
            case .volumeUp:
                self.changeVolume(up: true)
            case .volumeDown:
                self.changeVolume(up: false)
            case .mute:
                self.toggleMute()
            }
        }
    }

    private func discoverTarget() {
        let outputName = CoreAudioOutput.defaultOutputDeviceName()
        let candidates = AppleSiliconDDC.getIoregServicesForMatching().filter {
            $0.service != nil && !$0.productName.isEmpty
        }
        let ordered = candidates.sorted { left, right in
            let leftMatches = outputName.map { left.productName.caseInsensitiveCompare($0) == .orderedSame } ?? false
            let rightMatches = outputName.map { right.productName.caseInsensitiveCompare($0) == .orderedSame } ?? false
            return leftMatches && !rightMatches
        }

        let matchingOutput = ordered.first {
            guard let outputName else { return false }
            return $0.productName.caseInsensitiveCompare(outputName) == .orderedSame
        }
        guard let candidate = matchingOutput ?? (ordered.count == 1 ? ordered[0] : nil) else {
            publish(MonitorVolumeStatus(
                available: false,
                monitorName: nil,
                level: nil,
                muted: false,
                message: "Could not match the audio output to a DDC display"
            ))
            return
        }

        // Some monitors accept DDC writes but return malformed Get VCP
        // replies. Use a cached level for those
        // write-only displays instead of rejecting an otherwise valid target.
        let readVolume = AppleSiliconDDC.read(service: candidate.service, command: VCP.volume)
        let hasValidRead = readVolume.map { $0.max > 0 && $0.current <= $0.max } ?? false
        let maximum = hasValidRead ? readVolume!.max : 100
        let cachedLevel = storedLevel(for: candidate) ?? (1.0 / 16.0)
        let current = hasValidRead
            ? readVolume!.current
            : UInt16((cachedLevel * Double(maximum)).rounded())
        let muteValues = hasValidRead
            ? AppleSiliconDDC.read(service: candidate.service, command: VCP.mute)
            : nil
        // Never send hardware mute to a write-only display. Some monitors
        // accept the command but cannot be reliably unmuted without readable
        // state. Volume zero provides a safe, reversible mute fallback.
        let supportsMute = hasValidRead && (muteValues.map { $0.current == 1 || $0.current == 2 } ?? false)
        let muted = hasValidRead ? (supportsMute && muteValues?.current == 1) : current == 0
        let stored = storedLastVolume(for: candidate, maximum: maximum)

        target = Target(
            display: candidate,
            currentVolume: min(current, maximum),
            maximumVolume: maximum,
            isMuted: muted,
            supportsMute: supportsMute,
            lastNonZeroVolume: current > 0 ? min(current, maximum) : stored
        )
        let mode = hasValidRead ? "read/write" : "write-only"
        publishCurrent(message: "Controlling \(candidate.productName) (\(mode) DDC)")
    }

    private func changeVolume(up: Bool) {
        guard var target else { return }
        let step = max(UInt16(1), UInt16((Double(target.maximumVolume) / 16.0).rounded()))
        let baseVolume = target.isMuted ? target.lastNonZeroVolume : target.currentVolume
        let newVolume: UInt16
        if up {
            newVolume = min(target.maximumVolume, baseVolume.addingReportingOverflow(step).overflow
                ? target.maximumVolume
                : baseVolume + step)
        } else {
            newVolume = baseVolume > step ? baseVolume - step : 0
        }

        if target.isMuted, newVolume > 0, target.supportsMute {
            guard AppleSiliconDDC.write(service: target.display.service, command: VCP.mute, value: 2) else {
                publishError(for: target, message: "Could not unmute \(target.display.productName)")
                return
            }
            target.isMuted = false
        }

        guard newVolume != target.currentVolume else {
            self.target = target
            showOSD(for: target)
            return
        }

        guard AppleSiliconDDC.write(service: target.display.service, command: VCP.volume, value: newVolume) else {
            publishError(for: target, message: "DDC volume write failed")
            return
        }

        target.currentVolume = newVolume
        if newVolume == 0 {
            if target.supportsMute {
                _ = AppleSiliconDDC.write(service: target.display.service, command: VCP.mute, value: 1)
            }
            target.isMuted = true
        } else {
            target.isMuted = false
            target.lastNonZeroVolume = newVolume
            storeLastVolume(newVolume, for: target.display)
        }
        storeLevel(target.currentVolume, maximum: target.maximumVolume, for: target.display)
        self.target = target
        publishCurrent(message: "Controlling \(target.display.productName)")
        showOSD(for: target)
    }

    private func toggleMute() {
        guard var target else { return }

        if target.isMuted || target.currentVolume == 0 {
            let restored = max(UInt16(1), min(target.maximumVolume, target.lastNonZeroVolume))
            if target.supportsMute {
                _ = AppleSiliconDDC.write(service: target.display.service, command: VCP.mute, value: 2)
            }
            guard AppleSiliconDDC.write(service: target.display.service, command: VCP.volume, value: restored) else {
                publishError(for: target, message: "DDC unmute write failed")
                return
            }
            target.currentVolume = restored
            target.isMuted = false
        } else {
            target.lastNonZeroVolume = target.currentVolume
            storeLastVolume(target.currentVolume, for: target.display)
            guard AppleSiliconDDC.write(service: target.display.service, command: VCP.volume, value: 0) else {
                publishError(for: target, message: "DDC mute write failed")
                return
            }
            if target.supportsMute {
                _ = AppleSiliconDDC.write(service: target.display.service, command: VCP.mute, value: 1)
            }
            target.currentVolume = 0
            target.isMuted = true
        }

        storeLevel(target.currentVolume, maximum: target.maximumVolume, for: target.display)
        self.target = target
        publishCurrent(message: "Controlling \(target.display.productName)")
        showOSD(for: target)
    }

    private func level(for target: Target) -> Float {
        guard target.maximumVolume > 0 else { return 0 }
        return Float(target.currentVolume) / Float(target.maximumVolume)
    }

    private func publishCurrent(message: String) {
        guard let target else { return }
        publish(MonitorVolumeStatus(
            available: true,
            monitorName: target.display.productName,
            level: target.isMuted ? 0 : level(for: target),
            muted: target.isMuted,
            message: message
        ))
    }

    private func publishError(for target: Target, message: String) {
        publish(MonitorVolumeStatus(
            available: true,
            monitorName: target.display.productName,
            level: target.isMuted ? 0 : level(for: target),
            muted: target.isMuted,
            message: message
        ))
    }

    private func publish(_ status: MonitorVolumeStatus) {
        logger.info("\(status.message, privacy: .public)")
        DispatchQueue.main.async { [weak self] in self?.onStatusChange?(status) }
    }

    private func showOSD(for target: Target) {
        let shownLevel = target.isMuted ? Float(0) : level(for: target)
        DispatchQueue.main.async { [weak self] in
            self?.onOSD?(shownLevel, target.isMuted, target.display.productName)
        }
    }

    private func displayIdentity(_ display: AppleSiliconDDC.IOregService) -> String {
        display.alphanumericSerialNumber.isEmpty ? display.edidUUID : display.alphanumericSerialNumber
    }

    private func preferenceKey(for display: AppleSiliconDDC.IOregService) -> String {
        "lastNonZeroVolume.\(displayIdentity(display))"
    }

    private func levelPreferenceKey(for display: AppleSiliconDDC.IOregService) -> String {
        "volumeLevel.\(displayIdentity(display))"
    }

    private func storedLevel(for display: AppleSiliconDDC.IOregService) -> Double? {
        UserDefaults.standard.object(forKey: levelPreferenceKey(for: display)) as? Double
    }

    private func storeLevel(_ volume: UInt16, maximum: UInt16, for display: AppleSiliconDDC.IOregService) {
        guard maximum > 0 else { return }
        UserDefaults.standard.set(Double(volume) / Double(maximum), forKey: levelPreferenceKey(for: display))
    }

    private func storedLastVolume(for display: AppleSiliconDDC.IOregService, maximum: UInt16) -> UInt16 {
        let value = UserDefaults.standard.integer(forKey: preferenceKey(for: display))
        return value > 0 ? min(maximum, UInt16(clamping: value)) : max(UInt16(1), maximum / 16)
    }

    private func storeLastVolume(_ value: UInt16, for display: AppleSiliconDDC.IOregService) {
        UserDefaults.standard.set(Int(value), forKey: preferenceKey(for: display))
    }
}
