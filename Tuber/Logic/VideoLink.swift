import Foundation

enum VideoLink {
    /// Extracts an 11-char video ID from youtu.be, watch, shorts, live and embed links.
    static func videoID(from url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?
        if host == "youtu.be" {
            candidate = parts.first
        } else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            if parts.first == "watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]) {
                candidate = parts[1]
            }
        }
        guard let id = candidate, isValidID(id) else { return nil }
        return id
    }

    /// A video ID is exactly 11 characters of [A-Za-z0-9_-].
    static func isValidID(_ id: String) -> Bool {
        id.count == 11 && id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_"
        }
    }

    /// Finds the first video link inside arbitrary shared text.
    static func videoID(fromText text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        for match in detector?.matches(in: text, range: range) ?? [] {
            if let url = match.url, let id = videoID(from: url) { return id }
        }
        return nil
    }
}
