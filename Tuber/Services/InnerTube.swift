import Foundation

/// Anonymous calls to YouTube's internal web API (no key, no account).
enum InnerTube {
    static func post(_ endpoint: String, body: [String: Any], language: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload = body
        payload["context"] = ["client": ["clientName": "WEB", "clientVersion": "2.20260708.00.00",
                                         "hl": language ?? Locale.current.language.languageCode?.identifier ?? "en"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Collects every value stored under `key` anywhere in the JSON tree.
    static func find(_ key: String, in object: Any) -> [[String: Any]] {
        var found: [[String: Any]] = []
        func walk(_ o: Any) {
            if let dict = o as? [String: Any] {
                for (k, v) in dict {
                    if k == key, let match = v as? [String: Any] { found.append(match) } else { walk(v) }
                }
            } else if let array = o as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        return found
    }

    static func text(_ object: Any?) -> String {
        guard let dict = object as? [String: Any] else { return "" }
        if let simple = dict["simpleText"] as? String { return simple }
        let runs = dict["runs"] as? [[String: Any]] ?? []
        return runs.compactMap { $0["text"] as? String }.joined()
    }
}
