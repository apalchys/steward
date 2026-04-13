import AppKit
import SwiftUI

struct HotKeyRecorderView: View {
    @Binding var hotKey: AppHotKey
    let defaultHotKey: AppHotKey
    let title: String
    let validate: (AppHotKey) -> AppHotKeyValidationError?

    @State private var isRecording = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsListRow(title: title) {
                Button(action: startRecording) {
                    HStack(spacing: 10) {
                        Text(isRecording ? "Press key or mouse" : hotKey.displayValue)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)

                        Image(systemName: isRecording ? "circle.fill" : "keyboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minWidth: 220, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isRecording
                                    ? Color.accentColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.8),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            if hotKey != defaultHotKey {
                SettingsListDivider()
                SettingsListRow(title: "Default Shortcut") {
                    Button("Restore") {
                        apply(defaultHotKey)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            if let validationMessage {
                SettingsListDivider()
                SettingsListInfoRow(
                    text: validationMessage,
                    foregroundStyle: .red
                )
            }
        }
        .background(
            HotKeyCaptureView(isRecording: $isRecording) { capturedHotKey in
                apply(capturedHotKey)
            }
        )
    }

    private func startRecording() {
        validationMessage = nil
        isRecording = true
    }

    private func apply(_ candidate: AppHotKey) {
        isRecording = false

        if let validationError = validate(candidate) {
            validationMessage = validationError.errorDescription
            return
        }

        hotKey = candidate
        validationMessage = nil
    }
}

private struct HotKeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (AppHotKey) -> Void

    func makeNSView(context: Context) -> HotKeyCaptureNSView {
        let view = HotKeyCaptureNSView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.isRecording = isRecording
    }
}

@MainActor
private final class HotKeyCaptureNSView: NSView {
    private static let escapeKeyCode: UInt32 = 53

    var onCapture: ((AppHotKey) -> Void)?
    var isRecording = false {
        didSet {
            if isRecording {
                installMouseCaptureMonitor()
                window?.makeFirstResponder(self)
            } else {
                removeMouseCaptureMonitor()
            }

            guard isRecording else {
                return
            }
        }
    }
    private var localMouseCaptureMonitor: Any?
    private var globalMouseCaptureMonitor: Any?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if isRecording {
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == Self.escapeKeyCode {
            isRecording = false
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        isRecording = false
        onCapture?(
            AppHotKey(
                carbonKeyCode: UInt32(event.keyCode),
                carbonModifiers: modifiers.carbonFlags
            )
        )
    }

    deinit {
        MainActor.assumeIsolated {
            removeMouseCaptureMonitor()
        }
    }

    private func installMouseCaptureMonitor() {
        guard localMouseCaptureMonitor == nil, globalMouseCaptureMonitor == nil else {
            return
        }

        localMouseCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            guard let self else {
                return event
            }

            guard self.isRecording else {
                return event
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            self.isRecording = false
            self.onCapture?(
                AppHotKey(
                    mouseButtonNumber: Int(event.buttonNumber),
                    carbonModifiers: modifiers.carbonFlags
                )
            )
            return nil
        }

        globalMouseCaptureMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) {
            [weak self] event in
            guard let self else {
                return
            }

            guard self.isRecording else {
                return
            }

            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            self.isRecording = false
            self.onCapture?(
                AppHotKey(
                    mouseButtonNumber: Int(event.buttonNumber),
                    carbonModifiers: modifiers.carbonFlags
                )
            )
        }
    }

    private func removeMouseCaptureMonitor() {
        if let localMouseCaptureMonitor {
            NSEvent.removeMonitor(localMouseCaptureMonitor)
            self.localMouseCaptureMonitor = nil
        }
        if let globalMouseCaptureMonitor {
            NSEvent.removeMonitor(globalMouseCaptureMonitor)
            self.globalMouseCaptureMonitor = nil
        }
    }
}
