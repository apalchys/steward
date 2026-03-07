import AppKit
import SwiftUI

struct ContinuousSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let textField = NSSecureTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .default
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        nsView.placeholderString = placeholder

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
}

extension ContinuousSecureField {
    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSSecureTextField else {
                return
            }

            text = textField.stringValue
        }
    }
}
