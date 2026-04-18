import Cocoa
import Metal
import MetalKit
import QuartzCore

// How it works:
//   1. Creates a borderless, click-through NSWindow covering the screen
//   2. Adds a CAMetalLayer with EDR enabled (rgba16Float + extendedLinearDisplayP3)
//   3. Sets compositingFilter = "multiplyBlendMode"
//   4. Fills the layer with a color value > 1.0 (e.g. 2.0 = double brightness)
//   5. macOS composites: result = overlay × underlying pixel → brighter output
//
// Usage:
//   swift glow.swift [brightness]    (default: 2.0, range: 1.0–3.0)

let brightnessKey = "brightness"
let defaults = UserDefaults(suiteName: "com.glow")!

func clampBrightness(_ v: Double) -> Double { min(max(v, 1.0), 3.0) }

let initialBrightness: Double = {
    if CommandLine.arguments.count > 1 {
        return clampBrightness(Double(CommandLine.arguments[1]) ?? 2.0)
    }
    let saved = defaults.double(forKey: brightnessKey)
    return saved > 0 ? clampBrightness(saved) : 2.0
}()

let brightnessPresets: [(label: String, value: Double)] = [
    ("125%", 1.25), ("150%", 1.50), ("175%", 1.75),
    ("200%", 2.00), ("250%", 2.50), ("300%", 3.00),
]

let lockPath = "/tmp/com.glow.lock"
if let pidStr = try? String(contentsOfFile: lockPath, encoding: .utf8),
   let pid = pid_t(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
   kill(pid, 0) == 0 {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    sysctl(&mib, 4, &info, &size, nil, 0)
    let name = withUnsafeBytes(of: info.kp_proc.p_comm) {
        String(bytes: $0.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
    }
    if name == "glow" {
        fputs("glow is already running (PID \(pid)).\n", stderr)
        exit(0)
    }
}
try? String(ProcessInfo.processInfo.processIdentifier)
    .write(toFile: lockPath, atomically: true, encoding: .utf8)

guard let screen = NSScreen.main else {
    fputs("No main screen found.\n", stderr)
    exit(1)
}

let edr = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
if edr <= 1.0 {
    fputs("⚠ This display does not support EDR/XDR brightness.\n", stderr)
    fputs("  Supported displays: MacBook Pro with Liquid Retina XDR, Pro Display XDR.\n", stderr)
    exit(1)
}

// ── Metal-backed overlay view ──
final class EDRView: NSView {
    private var metalLayer: CAMetalLayer!
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var frameLink: CADisplayLink?

    var multiplier: Double {
        didSet {
            defaults.set(multiplier, forKey: brightnessKey)
            render()
        }
    }
    var isActive: Bool = true { didSet { render() } }

    init(frame: NSRect, multiplier: Double) {
        self.multiplier = multiplier
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { frameLink?.invalidate() }

    private func setup() {
        wantsLayer = true
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!

        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.backgroundColor = CGColor.clear
        metalLayer.displaySyncEnabled = true
        metalLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]

        layer = metalLayer
        metalLayer.compositingFilter = "multiplyBlendMode"

        let link = self.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        frameLink = link
    }

    @objc private func tick() { render() }

    func render() {
        guard let metalLayer, let commandQueue,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = drawable.texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store

        let v = isActive ? multiplier : 1.0
        let a = isActive ? 1.0 : 0.0
        desc.colorAttachments[0].clearColor = MTLClearColor(red: v, green: v, blue: v, alpha: a)

        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc)!
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    override func layout() {
        super.layout()
        guard let metalLayer else { return }
        metalLayer.frame = bounds
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        render()
    }
}

// ── Menu bar controller ──
final class MenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let edrView: EDRView
    private var toggleItem: NSMenuItem!
    private var presetItems: [NSMenuItem] = []

    init(edrView: EDRView) {
        self.edrView = edrView
        super.init()
        buildMenu()
        updateIcon()
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Brillo", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for preset in brightnessPresets {
            let item = NSMenuItem(
                title: preset.label,
                action: #selector(selectPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.value
            item.isEnabled = true
            if abs(preset.value - edrView.multiplier) < 0.01 {
                item.state = .on
            }
            presetItems.append(item)
            menu.addItem(item)
        }

        menu.addItem(.separator())

        toggleItem = NSMenuItem(
            title: "Pausar",
            action: #selector(toggleActive),
            keyEquivalent: "p"
        )
        toggleItem.keyEquivalentModifierMask = .command
        toggleItem.target = self
        toggleItem.isEnabled = true
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        edrView.multiplier = value
        presetItems.forEach { $0.state = .off }
        sender.state = .on
    }

    @objc private func toggleActive() {
        edrView.isActive.toggle()
        toggleItem.title = edrView.isActive ? "Pausar" : "Activar"
        updateIcon()
    }

    private func updateIcon() {
        let name = edrView.isActive ? "sun.max.fill" : "sun.min"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            image.isTemplate = true
            statusItem.button?.image = image
            statusItem.button?.title = ""
        } else {
            statusItem.button?.title = edrView.isActive ? "V" : "v"
        }
    }
}

// ── Overlay window ──
let frame = screen.frame
let window = NSWindow(
    contentRect: frame,
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
window.isOpaque = false
window.backgroundColor = .clear
window.ignoresMouseEvents = true
window.level = .screenSaver
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
window.hasShadow = false
window.hidesOnDeactivate = false
window.animationBehavior = .none

let snappedBrightness = brightnessPresets.map(\.value)
    .min(by: { abs($0 - initialBrightness) < abs($1 - initialBrightness) }) ?? 2.0

let edrView = EDRView(frame: frame, multiplier: snappedBrightness)
window.contentView = edrView
window.orderFrontRegardless()

_ = __NSApplicationLoad()
NSApp.setActivationPolicy(.accessory)

NotificationCenter.default.addObserver(
    forName: NSApplication.willTerminateNotification,
    object: nil, queue: nil
) { _ in try? FileManager.default.removeItem(atPath: lockPath) }

var menuController: MenuController?
DispatchQueue.main.async {
    menuController = MenuController(edrView: edrView)
}

NSApp.run()
