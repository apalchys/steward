import AppKit
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
    private var keyMonitor: Any?

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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 126: // arrow up
            viewModel.moveUp()
            return true
        case 125: // arrow down
            viewModel.moveDown()
            return true
        case 36, 76: // return, numpad enter
            viewModel.selectHighlighted()
            return true
        case 53: // escape
            viewModel.dismiss()
            return true
        default:
            if let characters = event.charactersIgnoringModifiers,
                let digit = characters.first?.wholeNumberValue,
                digit >= 1, digit <= 9
            {
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
