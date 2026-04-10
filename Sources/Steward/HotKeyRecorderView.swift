import AppKit
import SwiftUI

struct HotKeyRecorderView: View {
    @Binding var hotKey: AppHotKey
    let defaultHotKey: AppHotKey
    let validate: (AppHotKey) -> AppHotKeyValidationError?

    @State private var isRecording = false
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(action: startRecording) {
                    Text(isRecording ? "Type shortcut" : hotKey.displayValue)
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)

                Button("Restore Default") {
                    apply(defaultHotKey)
                }
                .buttonStyle(.bordered)
                .disabled(hotKey == defaultHotKey)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Hold to record, release to transcribe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            guard isRecording else {
                return
            }

            window?.makeFirstResponder(self)
        }
    }

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
        onCapture?(
            AppHotKey(
                carbonKeyCode: UInt32(event.keyCode),
                carbonModifiers: modifiers.carbonFlags
            )
        )
    }
}
