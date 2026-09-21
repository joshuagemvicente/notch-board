import Foundation
import UniformTypeIdentifiers

/// Shared card-id pasteboard helpers for island drag-and-drop.
///
/// `NSItemProvider(object: NSString)` only advertises `public.utf8-plain-text`.
/// Loading with `public.plain-text` alone returns nil on macOS — drops appear to
/// "accept" then silently do nothing. Always prefer utf8 / `loadObject(NSString)`.
enum CardDragPayload {
    static var dropTypes: [UTType] { [.utf8PlainText, .plainText, .text] }

    static func itemProvider(cardID: String) -> NSItemProvider {
        let trimmed = cardID.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = NSItemProvider()
        provider.registerObject(trimmed as NSString, visibility: .all)
        if let data = trimmed.data(using: .utf8) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.utf8PlainText.identifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    /// Returns `true` if a load was started. `completion` runs on the main actor.
    @discardableResult
    static func loadCardID(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor (String) -> Void
    ) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let raw = Self.string(from: object as Any?) else { return }
                let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { return }
                Task { @MainActor in completion(id) }
            }
            return true
        }

        let typeIDs = [
            UTType.utf8PlainText.identifier,
            UTType.plainText.identifier,
            UTType.text.identifier,
        ]
        guard let typeID = typeIDs.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
            guard let raw = Self.string(from: item as Any?) else { return }
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return }
            Task { @MainActor in completion(id) }
        }
        return true
    }

    /// Parse AppKit pasteboard payloads (Data / String / NSString / URL).
    static func string(from item: Any?) -> String? {
        if let string = item as? String {
            return string
        }
        if let string = item as? NSString {
            return string as String
        }
        if let data = item as? Data {
            if let utf8 = String(data: data, encoding: .utf8) {
                return utf8
            }
            return String(data: data, encoding: .utf16)
        }
        if let url = item as? URL {
            return url.isFileURL ? url.path : url.absoluteString
        }
        return nil
    }
}
