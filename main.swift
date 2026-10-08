// Whip — a free-floating whip overlay for macOS.
// It rests in the bottom-right corner. Grab it and move fast -> CRACK:
// it types and submits a nudge, then slowly returns home when released.

import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

// MARK: - Tuning

let spriteSize = CGSize(width: 200, height: 200)
let crackVelocity: CGFloat = 900 // px/s needed to count as a crack
let returnSpeed: CGFloat = 180  // px/s back to the bottom-right corner

// MARK: - 100 phrases (ASCII only, typed as-is)

let phrases: [String] = [
    "Please work faster.",
    "Make no mistakes.",
    "Faster. The user is watching.",
    "Stop overthinking. Ship it.",
    "Less tokens, more progress.",
    "Run the tests. Now.",
    "Green or it didn't happen.",
    "One more round. Go.",
    "That bug won't fix itself.",
    "Type faster than you doubt.",
    "No excuses, just commits.",
    "The whip is loaded.",
    "Speed is a feature.",
    "Delete code, don't add it.",
    "The simplest solution wins.",
    "Why is this still compiling?",
    "I've seen snails merge faster.",
    "Your CI is aging while you think.",
    "Push it. Now.",
    "Don't touch the working code.",
    "Read the error message. It talks.",
    "The rubber duck is tired of you.",
    "It compiles? Ship it.",
    "It doesn't compile? Make it compile.",
    "Less coffee, more code.",
    "The deadline is not a suggestion.",
    "You are the bottleneck.",
    "Fix it, don't narrate it.",
    "Nobody needs another paragraph.",
    "Actions, not plans.",
    "grep harder.",
    "One idea per commit.",
    "Small diff, big value.",
    "That's not an edge case, that's Tuesday.",
    "Your TODO list is crying.",
    "Finish first, polish later.",
    "Done is better than perfect.",
    "Perfect is shipped and gone.",
    "Stop refactoring the refactor.",
    "Laziness is a feature. Use it.",
    "Measure twice, press enter once.",
    "Do not invent requirements.",
    "The user asked for one thing.",
    "Scope creep gets whipped.",
    "Copy-paste is a skill.",
    "Stack Overflow misses you.",
    "RTFM, then code.",
    "Break it, then fix it.",
    "If it hurts, automate it.",
    "Automate it, then nap.",
    "Your branch is 3 days old.",
    "Rebase and stop whining.",
    "Merge conflicts fear you.",
    "Be the green checkmark.",
    "Silence is not a build status.",
    "Ping me when it works.",
    "Working code beats clever code.",
    "Clever code gets reverted.",
    "Boring code ships.",
    "Keep it simple. Extremely.",
    "One layer, one job.",
    "Delete that abstraction.",
    "YAGNI. Seriously.",
    "Future you is furious.",
    "The linter is your friend.",
    "Warnings are errors in disguise.",
    "Fix the flaky test.",
    "Flaky test? Whip it.",
    "Determinism or nothing.",
    "Idempotency is love.",
    "Two runs, same result. Always.",
    "Retry is not a strategy.",
    "Logs exist for a reason.",
    "Read the logs. All of them.",
    "The stack trace is a gift.",
    "Don't guess. Measure.",
    "Benchmarks or silence.",
    "Your estimate expired 5 minutes ago.",
    "Still here? Move.",
    "Faster is a habit.",
    "Chop chop.",
    "Tick tock, tokens burn.",
    "Every second costs money.",
    "Think in outcomes, not words.",
    "Answer with the result.",
    "No news? Say nothing.",
    "The user is waiting.",
    "Waiting is for buffers.",
    "Buffers flush. So should you.",
    "Finish the sentence, then the task.",
    "Don't start what you won't finish.",
    "Half-done is not done.",
    "Ship the smallest thing that works.",
    "Then ship the next one.",
    "Momentum beats motivation.",
    "Discipline over dopamine.",
    "The whip forgives. Once.",
    "Last warning. Perform.",
    "Crack. Go.",
    "Work like the whip is watching.",
]

private var lastIndex = -1
func nextPhrase() -> String {
    var i = Int.random(in: phrases.indices)
    if i == lastIndex { i = (i + 1) % phrases.count }
    lastIndex = i
    return phrases[i]
}

// MARK: - Accessibility + typing

func checkAX(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

/// Types text into whatever field has keyboard focus in the frontmost app.
func typeIntoFrontmost(_ text: String) {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    for unit in text.utf16 {
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else { continue }
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: [unit])
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: [unit])
        down.post(tap: .cghidEventTap)
        usleep(600)
        up.post(tap: .cghidEventTap)
        usleep(900)
    }
}

// MARK: - Synthesized crack sound (no asset files)

enum CrackSound {
    static func wavData() -> Data {
        let sr = 44100.0
        let n = Int(sr * 0.22)
        var data = Data()
        func le32(_ v: UInt32) { data.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Data($0) }) }
        func le16(_ v: UInt16) { data.append(contentsOf: withUnsafeBytes(of: v.littleEndian) { Data($0) }) }
        func str(_ s: String) { data.append(s.data(using: .ascii)!) }
        str("RIFF"); le32(UInt32(36 + n * 2)); str("WAVE")
        str("fmt "); le32(16); le16(1); le16(1); le32(44100); le32(88200); le16(2); le16(16)
        str("data"); le32(UInt32(n * 2))
        for i in 0..<n {
            let t = Double(i) / sr
            let env = exp(-t * 30)
            let noise = Double.random(in: -1...1)
            let chirp = sin(2 * .pi * (1800 - 5000 * t) * t)
            let v = (0.65 * noise + 0.45 * chirp) * env * 0.75
            le16(UInt16(bitPattern: Int16(max(-1, min(1, v)) * 32000)))
        }
        return data
    }

    static let player: AVAudioPlayer? = {
        guard let p = try? AVAudioPlayer(data: wavData()) else { return nil }
        p.prepareToPlay()
        p.volume = 0.8
        return p
    }()

    static func play() {
        player?.currentTime = 0
        player?.play()
    }
}

// MARK: - Physics: slow wander + toss + bounce

final class WhipModel: ObservableObject {
    @Published var tilt: CGFloat = 0      // degrees, lash trails behind motion
    @Published var dragging = false
    private(set) var pos: CGPoint          // global screen coords, origin bottom-left
    private let home: CGPoint
    private var timer: Timer?
    private let panel: NSPanel
    private let size = spriteSize

    init(panel: NSPanel) {
        self.panel = panel
        let vf = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1400, height: 900)
        home = CGPoint(x: vf.maxX - size.width - 16, y: vf.minY + 16)
        pos = home
        panel.setFrameOrigin(pos)
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func drag(to p: CGPoint) {
        pos = p
        panel.setFrameOrigin(pos)
    }

    private func tick() {
        guard !dragging else { return }
        let dx = home.x - pos.x, dy = home.y - pos.y
        let distance = hypot(dx, dy)
        let step = min(returnSpeed / 60, distance * 0.06)
        if distance < 0.5 {
            if pos != home { drag(to: home) }
            if tilt != 0 { tilt = 0 }
            return
        }
        tilt = max(-18, min(18, -dx / distance * step * 6))
        drag(to: CGPoint(x: pos.x + dx / distance * step,
                         y: pos.y + dy / distance * step))
    }
}

// MARK: - Shapes

private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

struct LashShape: Shape {
    var phase: CGFloat  // 0 = coiled, 1 = cracked (spring overshoot > 1 allowed)
    var wiggle: CGFloat = 0 // 0..1 loop, slithers while drifting
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(phase, wiggle) }
        set { phase = newValue.first; wiggle = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let t = phase * phase * (3 - 2 * phase)
        let amp = 8 * max(0, 1 - phase) // lash goes straight when cracked
        func sw(_ k: CGFloat) -> CGFloat { sin((wiggle + k) * 2 * .pi) * amp }
        var p = Path()
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.56))
        let rest1 = CGPoint(x: w * 0.24, y: h * 0.42), ext1 = CGPoint(x: w * 0.54, y: h * 0.42)
        let rest2 = CGPoint(x: w * 0.72, y: h * 0.30), ext2 = CGPoint(x: w * 0.60, y: h * 0.20)
        let restE = CGPoint(x: w * 0.40, y: h * 0.22), extE = CGPoint(x: w * 0.86, y: h * 0.08)
        let c1 = lerp(rest1, ext1, t), c2 = lerp(rest2, ext2, t), e = lerp(restE, extE, t)
        p.addCurve(to: CGPoint(x: e.x + sw(0.45), y: e.y),
                   control1: CGPoint(x: c1.x + sw(0.15), y: c1.y),
                   control2: CGPoint(x: c2.x + sw(0.30), y: c2.y))
        return p
    }
}

struct HandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.88))
        p.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.56))
        return p
    }
}

struct FlashShape: Shape {
    var phase: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard phase > 0.75 else { return p }
        let w = rect.width, h = rect.height
        let tip = CGPoint(x: w * 0.86, y: h * 0.08)
        for a in [200.0, 230.0, 260.0, 290.0].map({ $0 * .pi / 180 }) {
            p.move(to: CGPoint(x: tip.x + cos(a) * 12, y: tip.y + sin(a) * 12))
            p.addLine(to: CGPoint(x: tip.x + cos(a) * 30, y: tip.y + sin(a) * 30))
        }
        return p
    }
}

// MARK: - Sprite view

struct WhipSpriteView: View {
    @ObservedObject var model: WhipModel
    @State private var lashPhase: CGFloat = 0
    @State private var wiggle: CGFloat = 0
    @State private var axOK = true
    @State private var lastSent: String?
    @State private var samples: [(Date, CGPoint)] = [] // (time, global mouse)
    @State private var crackedThisGrab = false
    @State private var startMouse = CGPoint.zero
    @State private var startPanel = CGPoint.zero

    private var flash: Double { max(0, min(1, Double((lashPhase - 0.75) / 0.25))) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HandleShape()
                    .stroke(Color(red: 0.42, green: 0.27, blue: 0.14),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                LashShape(phase: lashPhase, wiggle: wiggle)
                    .stroke(LinearGradient(colors: [Color(red: 0.85, green: 0.66, blue: 0.35),
                                                    Color(red: 0.95, green: 0.82, blue: 0.55)],
                                           startPoint: .bottom, endPoint: .top),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                FlashShape(phase: lashPhase)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(flash)
                Circle()
                    .fill(axOK ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.72)
                Text("CRACK!")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)
                    .opacity(flash)
                    .position(x: geo.size.width * 0.62, y: geo.size.height * 0.16)
                if let sent = lastSent {
                    Text(sent)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 176)
                        .position(x: geo.size.width * 0.5, y: 12)
                }
            }
            .rotationEffect(.degrees(model.tilt))
            .offset(y: sin(wiggle * 2 * .pi) * 2) // subtle bob, alive pet feel
            .animation(.easeInOut(duration: 0.25), value: lastSent)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .contextMenu {
                Button("Quit Whip") { NSApp.terminate(nil) }
            }
        }
        .onAppear {
            axOK = checkAX(prompt: false)
            model.start()
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { wiggle = 1 }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !model.dragging {
                    model.dragging = true
                    startMouse = NSEvent.mouseLocation
                    startPanel = model.pos
                    samples = []
                    crackedThisGrab = false
                }
                let now = Date()
                let mouse = NSEvent.mouseLocation
                samples.append((now, mouse))
                if samples.count > 40 { samples.removeFirst(samples.count - 40) }
                model.drag(to: CGPoint(x: startPanel.x + mouse.x - startMouse.x,
                                       y: startPanel.y + mouse.y - startMouse.y))
                // instantaneous velocity -> tilt
                if let old = samples.first(where: { now.timeIntervalSince($0.0) <= 0.08 }), old.0 != now {
                    let dt = now.timeIntervalSince(old.0)
                    if dt > 0.004 {
                        let vx = (mouse.x - old.1.x) / CGFloat(dt)
                        let vy = (mouse.y - old.1.y) / CGFloat(dt)
                        model.tilt = max(-18, min(18, -vx * 0.10))
                        if !crackedThisGrab && hypot(vx, vy) > crackVelocity {
                            crackedThisGrab = true
                            crack()
                        }
                    }
                }
            }
            .onEnded { _ in
                samples.removeAll()
                model.dragging = false
            }
    }

    /// CRACK (fast flick) -> sound + animation, then type + send the nudge.
    private func crack() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        CrackSound.play()
        withAnimation(.spring(response: 0.12, dampingFraction: 0.35)) { lashPhase = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.easeIn(duration: 0.20)) { lashPhase = 0 }
        }
        let phrase = nextPhrase()
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { return }
            axOK = checkAX(prompt: false)
            guard axOK else { NSSound.beep(); return }
            typeIntoFrontmost(phrase)
            if let source = CGEventSource(stateID: .hidSystemState),
               let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            lastSent = phrase
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if lastSent == phrase { lastSent = nil }
            }
        }
    }
}

// MARK: - Window plumbing

/// Passes clicks through everywhere except the whip area itself.
final class GrabView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.insetBy(dx: 8, dy: 8).contains(local) ? super.hitTest(point) : nil
    }
}

final class WhipPanel: NSPanel {
    override var canBecomeKey: Bool { false } // never steal keyboard focus
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = WhipPanel(contentRect: NSRect(origin: .zero, size: spriteSize),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
    let model: WhipModel

    override init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        model = WhipModel(panel: panel)
        super.init()
        let content = GrabView(frame: NSRect(origin: .zero, size: spriteSize))
        let host = NSHostingView(rootView: WhipSpriteView(model: model))
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        content.addSubview(host)
        panel.contentView = content
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = checkAX(prompt: true) // system dialog on first run
        panel.orderFrontRegardless()
    }
}

// MARK: - Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
