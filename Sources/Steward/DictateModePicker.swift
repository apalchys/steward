@preconcurrency import AppKit
@preconcurrency import ApplicationServices
import SwiftUI

@MainActor
protocol DictateModePickerPresenting: AnyObject {
    var onModeSelected: ((UUID) -> Void)? { get set }
    var onDismissed: (() -> Void)? { get set }

    func show(modes: [DictateMode], activeModeID: UUID)
    func hide()
}

@MainActor
protocol DictateModePickerWindowing: AnyObject {
    var contentView: NSView? { get set }
    var isVisible: Bool { get }

    func setFrame(_ frame: NSRect, display: Bool)
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
}

extension NSPanel: DictateModePickerWindowing {}

@MainActor
final class DictateModePickerViewModel: ObservableObject {
    @Published private(set) var modes: [DictateMode] = []
    @Published var highlightedIndex: Int = 0
    @Published private(set) var activeModeID: UUID = DictateMode.defaultModeID

    var onSelect: ((UUID) -> Void)?
    var onDismiss: (() -> Void)?

    func configure(modes: [DictateMode], activeModeID: UUID) {
        self.modes = modes
        self.activeModeID = activeModeID
        highlightedIndex = modes.firstIndex(where: { $0.id == activeModeID }) ?? 0
    }

    func moveUp() {
        guard !modes.isEmpty else { return }
        highlightedIndex = (highlightedIndex - 1 + modes.count) % modes.count
    }

    func moveDown() {
        guard !modes.isEmpty else { return }
        highlightedIndex = (highlightedIndex + 1) % modes.count
    }

    func selectHighlighted() {
        guard modes.indices.contains(highlightedIndex) else { return }
        onSelect?(modes[highlightedIndex].id)
    }

    func selectByNumber(_ number: Int) {
        let index = number - 1
        guard modes.indices.contains(index) else { return }
        onSelect?(modes[index].id)
    }

    func dismiss() {
        onDismiss?()
    }
}

@MainActor
final class DictateModePickerController: DictateModePickerPresenting {
    private enum UI {
        static let width: CGFloat = 280
        static let rowHeight: CGFloat = 44
        static let verticalPadding: CGFloat = 8
        static let bottomMargin: CGFloat = 100
    }

    var onModeSelected: ((UUID) -> Void)? {
        didSet { viewModel.onSelect = onModeSelected }
    }

    var onDismissed: (() -> Void)? {
        didSet { viewModel.onDismiss = onDismissed }
    }

    private let viewModel = DictateModePickerViewModel()
    private let windowFactory: () -> any DictateModePickerWindowing
    private let screenProvider: () -> NSScreen?
    private var pickerWindow: (any DictateModePickerWindowing)?
    private var localKeyMonitor: Any?
    private var keyEventTap: CFMachPort?
    private var keyEventTapSource: CFRunLoopSource?

    init(
        windowFactory: (() -> any DictateModePickerWindowing)? = nil,
        screenProvider: (() -> NSScreen?)? = nil
    ) {
        self.windowFactory = windowFactory ?? { Self.makeWindow() }
        self.screenProvider = screenProvider ?? { NSScreen.main ?? NSScreen.screens.first }
    }

    func show(modes: [DictateMode], activeModeID: UUID) {
        guard !modes.isEmpty else { return }
        viewModel.configure(modes: modes, activeModeID: activeModeID)
        let window = window()
        positionWindow(window, modeCount: modes.count)
        window.orderFrontRegardless()
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        pickerWindow?.orderOut(nil)
    }

    private func window() -> any DictateModePickerWindowing {
        if let pickerWindow { return pickerWindow }
        let w = windowFactory()
        w.contentView = DictateModePickerHostingView(
            rootView: DictateModePickerView(model: viewModel)
        )
        pickerWindow = w
        return w
    }

    private func positionWindow(_ window: any DictateModePickerWindowing, modeCount: Int) {
        guard let screen = screenProvider() else { return }
        let height = CGFloat(modeCount) * UI.rowHeight + UI.verticalPadding * 2
        let visibleFrame = screen.visibleFrame
        let frame = NSRect(
            x: visibleFrame.midX - (UI.width / 2),
            y: visibleFrame.minY + UI.bottomMargin,
            width: UI.width,
            height: height
        )
        window.setFrame(frame, display: true)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()

        if installGlobalKeyEventTap() {
            return
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let keyEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), keyEventTapSource, .commonModes)
            self.keyEventTapSource = nil
        }

        if let keyEventTap {
            CFMachPortInvalidate(keyEventTap)
            self.keyEventTap = nil
        }
    }

    private func installGlobalKeyEventTap() -> Bool {
        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue

        guard
            let keyEventTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }

                    let controller = Unmanaged<DictateModePickerController>.fromOpaque(userInfo).takeUnretainedValue()
                    return MainActor.assumeIsolated {
                        controller.handleKeyEventTap(type: type, event: event)
                    }
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        guard let keyEventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, keyEventTap, 0) else {
            CFMachPortInvalidate(keyEventTap)
            return false
        }

        self.keyEventTap = keyEventTap
        self.keyEventTapSource = keyEventTapSource
        CFRunLoopAddSource(CFRunLoopGetMain(), keyEventTapSource, .commonModes)
        CGEvent.tapEnable(tap: keyEventTap, enable: true)
        return true
    }

    private func handleKeyEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            guard let nsEvent = NSEvent(cgEvent: event) else {
                return Unmanaged.passUnretained(event)
            }
            return handleKeyEvent(nsEvent) ? nil : Unmanaged.passUnretained(event)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let keyEventTap {
                CGEvent.tapEnable(tap: keyEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 126:  // arrow up
            viewModel.moveUp()
            return true
        case 125:  // arrow down
            viewModel.moveDown()
            return true
        case 36, 76:  // return, numpad enter
            viewModel.selectHighlighted()
            return true
        case 53:  // escape
            viewModel.dismiss()
            return true
        default:
            if let digit = DictateModePickerShortcut.modeNumber(for: event) {
                viewModel.selectByNumber(digit)
                return true
            }
            return false
        }
    }

    private static func makeWindow() -> any DictateModePickerWindowing {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: UI.width, height: 200)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        return panel
    }
}

enum DictateModePickerShortcut {
    private static let numberRowDigits: [Int: Int] = [
        18: 1,
        19: 2,
        20: 3,
        21: 4,
        23: 5,
        22: 6,
        26: 7,
        28: 8,
        25: 9,
    ]

    private static let keypadDigits: [Int: Int] = [
        83: 1,
        84: 2,
        85: 3,
        86: 4,
        87: 5,
        88: 6,
        89: 7,
        91: 8,
        92: 9,
    ]

    static func modeNumber(for event: NSEvent) -> Int? {
        if let digit = numberRowDigits[Int(event.keyCode)] ?? keypadDigits[Int(event.keyCode)] {
            return digit
        }

        for characters in [event.charactersIgnoringModifiers, event.characters] {
            if let digit = characters?.first?.wholeNumberValue, (1...9).contains(digit) {
                return digit
            }
        }

        return nil
    }
}

private final class DictateModePickerHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct DictateModePickerView: View {
    @ObservedObject var model: DictateModePickerViewModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.modes.enumerated()), id: \.element.id) { index, mode in
                DictateModePickerRow(
                    mode: mode,
                    index: index,
                    isActive: mode.id == model.activeModeID,
                    isHighlighted: index == model.highlightedIndex
                )
                .onTapGesture {
                    model.onSelect?(mode.id)
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct DictateModePickerRow: View {
    let mode: DictateMode
    let index: Int
    let isActive: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isActive ? Color.green : Color.clear)
                .frame(width: 8, height: 8)

            Text(mode.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(0.1) : Color.clear)
                .padding(.horizontal, 4)
        )
    }
}
