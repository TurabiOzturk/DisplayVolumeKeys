import AppKit

/// A lightweight, reusable volume HUD for systems where Apple's private OSD
/// no longer displays caller-supplied volume progress.
final class VolumeHUDController {
    private let panel: NSPanel
    private let hudView: VolumeHUDView
    private var hideWorkItem: DispatchWorkItem?

    init() {
        let size = NSSize(width: 280, height: 56)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        hudView = VolumeHUDView(frame: NSRect(origin: .zero, size: size))

        let container = NSView(frame: hudView.bounds)
        container.autoresizingMask = [.width, .height]

        let glass = NSVisualEffectView(frame: hudView.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.alphaValue = 0.52
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true

        let lightTint = NSView(frame: hudView.bounds)
        lightTint.autoresizingMask = [.width, .height]
        lightTint.wantsLayer = true
        lightTint.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        lightTint.layer?.cornerRadius = 16
        lightTint.layer?.masksToBounds = true

        container.addSubview(glass)
        container.addSubview(lightTint)
        container.addSubview(hudView)
        panel.contentView = container
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
    }

    func show(level: Float, muted: Bool, monitorName: String, on screen: NSScreen?) {
        precondition(Thread.isMainThread)
        hideWorkItem?.cancel()

        hudView.level = min(1, max(0, CGFloat(level)))
        hudView.muted = muted
        hudView.monitorName = monitorName
        hudView.needsDisplay = true

        position(on: screen ?? NSScreen.main)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.22
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.panel.orderOut(nil)
            })
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: workItem)
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 18
        )
        panel.setFrameOrigin(origin)
    }
}

private final class VolumeHUDView: NSView {
    private let leftSpeaker = NSImageView()
    private let rightSpeaker = NSImageView()

    var level: CGFloat = 0
    var muted = false {
        didSet { updateSpeakerImages() }
    }
    var monitorName = "External Display"

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for imageView in [leftSpeaker, rightSpeaker] {
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.contentTintColor = .white
            addSubview(imageView)
        }
        updateSpeakerImages()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        leftSpeaker.frame = NSRect(x: 13, y: 29, width: 16, height: 16)
        rightSpeaker.frame = NSRect(x: bounds.width - 29, y: 28, width: 18, height: 18)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = bounds
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16)
        shape.addClip()

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        NSString(string: monitorName).draw(
            in: NSRect(x: 14, y: 7, width: bounds.width - 28, height: 17),
            withAttributes: labelAttributes
        )

        let trackStart: CGFloat = 38
        let trackEnd = bounds.width - 38
        let trackY: CGFloat = 36
        let trackWidth = trackEnd - trackStart

        NSColor.white.withAlphaComponent(0.24).setFill()
        NSBezierPath(roundedRect: NSRect(x: trackStart, y: trackY, width: trackWidth, height: 3), xRadius: 1.5, yRadius: 1.5).fill()

        if !muted, level > 0 {
            NSColor.systemBlue.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: trackStart, y: trackY, width: max(3, trackWidth * level), height: 3),
                xRadius: 1.5,
                yRadius: 1.5
            ).fill()
        }

        NSColor.white.withAlphaComponent(0.16).setStroke()
        let highlight = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 15.5, yRadius: 15.5)
        highlight.lineWidth = 0.75
        highlight.stroke()
    }

    private func updateSpeakerImages() {
        leftSpeaker.image = symbolImage(named: muted ? "speaker.slash.fill" : "speaker.fill", pointSize: 13)
        rightSpeaker.image = symbolImage(named: "speaker.wave.3.fill", pointSize: 13)
    }

    private func symbolImage(named name: String, pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }
}
