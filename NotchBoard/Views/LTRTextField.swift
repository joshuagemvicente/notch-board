import SwiftUI
import AppKit

/// Plain LTR text field — SwiftUI `TextField` inside Form often inherits RTL
/// typing alignment from the system locale; AppKit does not.
struct LTRTextField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String
    var isSecure: Bool = false

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField
        if isSecure {
            field = NSSecureTextField(string: text)
        } else {
            field = NSTextField(string: text)
        }
        field.placeholderString = placeholder
        field.isBordered = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.focusRingType = .default
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        applyLTR(to: field)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        applyLTR(to: nsView)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private func applyLTR(to field: NSTextField) {
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        if let cell = field.cell as? NSTextFieldCell {
            cell.alignment = .left
            cell.baseWritingDirection = .leftToRight
            cell.wraps = false
            cell.isScrollable = true
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
