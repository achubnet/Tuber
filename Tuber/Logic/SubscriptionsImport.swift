import Foundation

/// Parses subscriptions.csv from Google Takeout (YouTube and YouTube Music → subscriptions).
enum SubscriptionsImport {
    struct Entry: Hashable {
        let id: String
        let title: String
    }

    enum ChannelRef: Hashable {
        case id(String)
        case handle(String)
    }

    struct ListItem: Hashable {
        let ref: ChannelRef
        let hidden: Bool
    }

    /// Simple list: one channel per line (@handle, channel URL or UC… ID).
    /// A leading "-" means subscribe but keep out of the feed. "#" starts a comment.
    static func parseList(_ text: String) -> [ListItem] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            let hidden = line.hasPrefix("-")
            if hidden { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            line = String(line.split(separator: " ").first ?? "")
            return channelRef(line).map { ListItem(ref: $0, hidden: hidden) }
        }
    }

    static func channelRef(_ token: String) -> ChannelRef? {
        if token.hasPrefix("@") { return .handle(String(token.dropFirst())) }
        if token.hasPrefix("UC"), token.count == 24 { return .id(token) }
        guard let url = URL(string: token.contains("://") ? token : "https://" + token),
              let host = url.host()?.lowercased(), host.hasSuffix("youtube.com") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if let first = parts.first, first.hasPrefix("@") { return .handle(String(first.dropFirst())) }
        if parts.count >= 2, parts[0] == "channel", parts[1].hasPrefix("UC") { return .id(parts[1]) }
        return nil
    }

    static func parse(_ csv: String) -> [Entry] {
        csv.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = split(String(line))
            guard fields.count >= 3, fields[0].hasPrefix("UC") else { return nil }
            return Entry(id: fields[0], title: fields[2])
        }
    }

    /// Splits one CSV line, honoring quoted fields with commas and doubled quotes.
    private static func split(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var quoted = false
        var chars = Array(line)[...]
        while let c = chars.popFirst() {
            if c == "\"" {
                if quoted, chars.first == "\"" { current.append("\""); chars.removeFirst() } else { quoted.toggle() }
            } else if c == ",", !quoted {
                fields.append(current); current = ""
            } else {
                current.append(c)
            }
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
