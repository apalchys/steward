import AppKit
import SwiftUI

enum VoiceRecordingPillState: Equatable {
    case recording(level: Float)
    case transcribing
}

@MainActor
protocol VoiceRecordingPillPresenting: AnyObject {
    var onCancel: (() -> Void)? { get set }
    var onConfirm: (() -> Void)? { get set }

    func showRecording(level: Float)
    func showTranscribing()
    func hide()
}

@MainActor
protocol VoiceRecordingPillWindowing: AnyObject {
    var contentView: NSView? { get set }
    var isVisible: Bool { get }

    func setFrame(_ frame: NSRect, display: Bool)
    func orderFrontRegardless()
    func orderOut(_ sender: Any?)
}

extension NSPanel: VoiceRecordingPillWindowing {}

@MainActor
final class VoiceRecordingPillViewModel: ObservableObject {
    @Published private(set) var state: VoiceRecordingPillState = .recording(level: 0)

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    func update(state: VoiceRecordingPillState) {
        self.state = state
    }

    func handleCancel() {
        onCancel?()
    }

    func handleConfirm() {
        onConfirm?()
    }
}

@MainActor
final class VoiceRecordingPillController: VoiceRecordingPillPresenting {
    private enum UI {
        static let size = CGSize(width: 228, height: 72)
        static let bottomMargin: CGFloat = 28
    }

    var onCancel: (() -> Void)? {
        didSet {
            viewModel.onCancel = onCancel
        }
    }

    var onConfirm: (() -> Void)? {
        didSet {
            viewModel.onConfirm = onConfirm
        }
    }

    var currentState: VoiceRecordingPillState {
        viewModel.state
    }

    private let viewModel = VoiceRecordingPillViewModel()
    private let windowFactory: () -> any VoiceRecordingPillWindowing
    private let screenProvider: () -> NSScreen?
    private var pillWindow: (any VoiceRecordingPillWindowing)?

    init(
        windowFactory: (() -> any VoiceRecordingPillWindowing)? = nil,
        screenProvider: (() -> NSScreen?)? = nil
    ) {
        self.windowFactory = windowFactory ?? { Self.makeWindow() }
        self.screenProvider = screenProvider ?? { NSScreen.main ?? NSScreen.screens.first }
    }

    func showRecording(level: Float) {
        viewModel.update(state: .recording(level: min(max(level, 0), 1)))
        presentWindow()
    }

    func showTranscribing() {
        viewModel.update(state: .transcribing)
        presentWindow()
    }

    func hide() {
        pillWindow?.orderOut(nil)
    }

    private func presentWindow() {
        let window = window()
        position(window)
        window.orderFrontRegardless()
    }

    private func window() -> any VoiceRecordingPillWindowing {
        if let pillWindow {
            return pillWindow
        }

        let pillWindow = windowFactory()
        pillWindow.contentView = NSHostingView(rootView: VoiceRecordingPillView(model: viewModel))
        self.pillWindow = pillWindow
        return pillWindow
    }

    private func position(_ window: any VoiceRecordingPillWindowing) {
        guard let screen = screenProvider() else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let frame = NSRect(
            x: visibleFrame.midX - (UI.size.width / 2),
            y: visibleFrame.minY + UI.bottomMargin,
            width: UI.size.width,
            height: UI.size.height
        )
        window.setFrame(frame, display: true)
    }

    private static func makeWindow() -> any VoiceRecordingPillWindowing {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: UI.size),
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

private struct VoiceRecordingPillView: View {
    @ObservedObject var model: VoiceRecordingPillViewModel

    var body: some View {
        HStack(spacing: 18) {
            Button(action: model.handleCancel) {
                CircleButtonContent(symbolName: "xmark")
            }
            .buttonStyle(.plain)
            .disabled(model.state == .transcribing)
            .opacity(model.state == .transcribing ? 0.45 : 1)

            centerContent

            Button(action: model.handleConfirm) {
                CircleButtonContent(symbolName: "checkmark")
            }
            .buttonStyle(.plain)
            .disabled(model.state == .transcribing)
            .opacity(model.state == .transcribing ? 0.45 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.94))
                .shadow(color: Color.black.opacity(0.28), radius: 18, y: 8)
        )
        .padding(8)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.state {
        case .recording(let level):
            VoiceRecordingLevelMeter(level: level)
        case .transcribing:
            VoiceRecordingBusyIndicator()
        }
    }
}

private struct CircleButtonContent: View {
    let symbolName: String

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 42, height: 42)

            Image(systemName: symbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.black)
        }
    }
}

private struct VoiceRecordingLevelMeter: View {
    let level: Float

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(barHeights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(opacity(for: index)))
                    .frame(width: 6, height: height)
            }
        }
        .frame(width: 72, height: 40)
    }

    private var barHeights: [CGFloat] {
        [12, 18, 28, 36, 28, 18, 12]
    }

    private func opacity(for index: Int) -> Double {
        let normalizedLevel = min(max(Double(level), 0), 1)
        let threshold = Double(index + 1) / Double(barHeights.count)
        return normalizedLevel + 0.2 >= threshold ? 1 : 0.35
    }
}

private struct VoiceRecordingBusyIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == 1 ? 0.8 : 0.5))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 72, height: 40)
    }
}
