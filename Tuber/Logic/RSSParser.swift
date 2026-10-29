import Foundation

struct FeedEntry: Sendable {
    let id: String
    let channelID: String
    let title: String
    let published: Date
    var isShort = false
}

enum RSSParser {
    static func parse(_ data: Data) throws -> (channelTitle: String, entries: [FeedEntry]) {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return (delegate.channelTitle, delegate.entries)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var channelTitle = ""
        var entries: [FeedEntry] = []
        private var inEntry = false
        private var text = ""
        private var fields: [String: String] = [:]
        private let dates = ISO8601DateFormatter()

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "entry" { inEntry = true; fields = [:] }
            if name == "link", inEntry, let href = attributes["href"] { fields["link"] = href }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "entry" {
                inEntry = false
                if let id = fields["yt:videoId"], let title = fields["title"],
                   let date = fields["published"].flatMap(dates.date(from:)) {
                    entries.append(FeedEntry(id: id, channelID: fields["yt:channelId"] ?? "", title: title, published: date,
                                             isShort: fields["link"]?.contains("/shorts/") == true))
                }
            } else if inEntry, name != "link" {
                fields[name] = value
            } else if name == "title", channelTitle.isEmpty {
                channelTitle = value
            }
            text = ""
        }
    }
}
