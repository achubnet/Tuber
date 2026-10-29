import AppIntents
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage(Settings.skipCategoriesKey) private var stored = Settings.defaultSkipCategories

    @AppStorage("appLanguage") private var language = "system"
    @State private var importing = false
    @State private var importResult: String?
    @State private var isImporting = false
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $language) {
                    Text("System").tag("system")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Русский").tag("ru")
                }
                .onChange(of: language) { _, value in
                    if value == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([value], forKey: "AppleLanguages")
                    }
                }
            } footer: {
                Text("Takes effect after you restart the app.")
            }
            Section {
                Button("Import subscriptions", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("A text file with one channel per line: @handle, channel link or ID. Put “-” before a channel to subscribe without showing it in the feed. subscriptions.csv from Google Takeout works too.")
            }
            Section {
                ShortcutsLink()
            } header: {
                Text("Siri")
            }
            Section {
                ForEach(Settings.allCategories, id: \.self) { category in
                    Toggle(PlayerModel.categoryName(category), isOn: binding(category))
                }
            } header: {
                Text("Skip automatically")
            } footer: {
                Text("Segment data comes from SponsorBlock.")
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            guard case .success(let url) = result else { return }
            isImporting = true
            Task {
                let r = await Subscriptions.importFile(at: url, context: context)
                isImporting = false
                importResult = r.map { String(localized: "Added: \($0.added), updated: \($0.updated), not found: \($0.failed)") }
                    ?? String(localized: "Could not read the file")
            }
        }
        .overlay { if isImporting { ProgressView().controlSize(.large) } }
        .alert(importResult ?? "", isPresented: Binding(get: { importResult != nil }, set: { if !$0 { importResult = nil } })) {}
    }

    private func binding(_ category: String) -> Binding<Bool> {
        Binding {
            stored.split(separator: ",").contains(Substring(category))
        } set: { on in
            var set = stored.split(separator: ",").map(String.init).filter { $0 != category }
            if on { set.append(category) }
            stored = set.joined(separator: ",")
        }
    }
}

enum Subscriptions {
    struct Result { var added = 0, updated = 0, failed = 0 }

    /// Imports a Takeout CSV or a simple channel list (see SubscriptionsImport.parseList).
    @MainActor
    static func importFile(at url: URL, context: ModelContext) async -> Result? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var wanted: [(id: String, title: String?, hidden: Bool)] = []
        var result = Result()
        if text.hasPrefix("Channel Id") {
            wanted = SubscriptionsImport.parse(text).map { ($0.id, $0.title, false) }
        } else {
            for item in SubscriptionsImport.parseList(text) {
                switch item.ref {
                case .id(let id): wanted.append((id, nil, item.hidden))
                case .handle(let handle):
                    if let id = await resolve(handle: handle) { wanted.append((id, nil, item.hidden)) } else { result.failed += 1 }
                }
            }
        }

        let existing = Dictionary(((try? context.fetch(FetchDescriptor<Channel>())) ?? []).map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        for w in wanted {
            if let channel = existing[w.id] {
                channel.hiddenFromFeed = w.hidden
                result.updated += 1
                continue
            }
            var title = w.title
            if title == nil { title = await FeedService.feed(channelID: w.id)?.title }
            guard let title, !title.isEmpty else { result.failed += 1; continue }
            let channel = Channel(id: w.id, title: title)
            channel.hiddenFromFeed = w.hidden
            context.insert(channel)
            result.added += 1
        }
        try? context.save()
        return result
    }

    /// @handle -> UC… channel ID.
    static func resolve(handle: String) async -> String? {
        let json = try? await InnerTube.post("navigation/resolve_url", body: ["url": "https://www.youtube.com/@\(handle)"])
        return ((json?["endpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
    }
}
