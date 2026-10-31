import AppIntents
import SwiftData
import SwiftUI

struct FeedView: View {
    @Query(sort: \Video.published, order: .reverse) private var videos: [Video]
    @Query private var channels: [Channel]
    @AppStorage("hideWatched") private var hideWatched = false
    @Environment(\.modelContext) private var context
    @State private var didRefresh = false
    @State private var loadingMore = false
    @State private var emptyStreak = 0

    var body: some View {
        let shown = channels.filter { !$0.hiddenFromFeed }
        let subscribed = Set(shown.map(\.id))
        let later = videos.filter { $0.watchLater && !$0.hidden }
        let mine = videos.filter { subscribed.contains($0.channelID) }
        let cutoff = FeedService.cutoff(channels: shown, videos: mine)
        let feed = mine.filter { !$0.hidden && !(hideWatched && $0.watched) && $0.published >= (cutoff ?? .distantPast) }
        let autoLoad = !shown.isEmpty && FeedPaging.canAutoLoad(hasMore: FeedService.hasMore(shown), emptyStreak: emptyStreak)
        let reachedEnd = !shown.isEmpty && !loadingMore && !autoLoad

        NavigationStack {
            List {
                if !later.isEmpty {
                    Section("Watch later") { rows(later) }
                }
                Section {
                    rows(feed)
                    if loadingMore, !feed.isEmpty {
                        Label("Loading older videos…", systemImage: "arrow.down.circle")
                            .labelStyle(LoadingLabelStyle())
                            .listRowSeparator(.hidden)
                    } else if autoLoad {
                        // Invisible trigger: appears at the bottom and asks for the next page.
                        Color.clear.frame(height: 1).listRowSeparator(.hidden)
                            .task(id: "\(String(describing: cutoff))-\(feed.count)-\(emptyStreak)") {
                                loadMore(before: cutoff, videos: mine, visible: feed.count)
                            }
                    } else if reachedEnd, !feed.isEmpty {
                        EndOfFeed(hideWatched: $hideWatched).listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if channels.isEmpty {
                    ContentUnavailableView("No channels yet", systemImage: "person.2",
                                           description: Text("Find channels in Search and subscribe."))
                } else if feed.isEmpty, later.isEmpty {
                    if reachedEnd {
                        ContentUnavailableView {
                            Label(hideWatched ? "No new videos" : "No videos yet", systemImage: "checkmark.circle")
                        } description: {
                            Text(hideWatched ? "You've watched everything. New videos will show up here."
                                             : "Pull down to refresh.")
                        } actions: {
                            if hideWatched { Button("Show watched") { hideWatched = false } }
                        }
                    } else {
                        ProgressView()
                    }
                }
            }
            .onChange(of: hideWatched) { emptyStreak = 0 }
            .navigationTitle("Feed")
            .toolbar {
                Menu {
                    Toggle("Hide watched", systemImage: "eye.slash", isOn: $hideWatched)
                } label: {
                    Image(systemName: hideWatched ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
            }
            .refreshable {
                emptyStreak = 0
                await FeedService.refresh(channels: channels, context: context)
            }
            .task {
                guard !didRefresh else { return }
                didRefresh = true
                await FeedService.refresh(channels: channels, context: context)
            }
            .navigationDestination(for: ChannelRef.self) { ChannelView(ref: $0) }
            .onChange(of: channels.count, initial: true) { TuberShortcuts.updateAppShortcutParameters() }
        }
    }

    private func rows(_ list: [Video]) -> some View {
        ForEach(list) { video in
            VideoCard(video: video)
                .videoActions(video)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        }
    }

    /// Loads the next page only for channels that hold the cutoff back.
    private func loadMore(before cutoff: Date?, videos: [Video], visible: Int) {
        guard !loadingMore else { return }
        var oldest: [String: Date] = [:]
        for v in videos { oldest[v.channelID] = min(oldest[v.channelID] ?? v.published, v.published) }
        let limiting = channels.filter { !$0.hiddenFromFeed }.filter {
            !FeedService.isFinished($0.id) && (cutoff == nil || (oldest[$0.id] ?? .distantFuture) >= cutoff!)
        }
        guard !limiting.isEmpty else { return }
        loadingMore = true
        Task {
            await FeedService.loadMore(channels: limiting, context: context)
            emptyStreak = FeedPaging.emptyStreak(visibleBefore: visible, visibleAfter: visibleCount(), streak: emptyStreak)
            loadingMore = false
        }
    }

    /// Same filter as the feed, recomputed after a page lands.
    private func visibleCount() -> Int {
        let shown = channels.filter { !$0.hiddenFromFeed }
        let ids = Set(shown.map(\.id))
        let mine = videos.filter { ids.contains($0.channelID) }
        let cutoff = FeedService.cutoff(channels: shown, videos: mine)
        return mine.filter { !$0.hidden && !(hideWatched && $0.watched) && $0.published >= (cutoff ?? .distantPast) }.count
    }
}

/// Footer under the last video when there is nothing more to show.
private struct EndOfFeed: View {
    @Binding var hideWatched: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Rectangle().fill(.quaternary).frame(height: 0.5)
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Rectangle().fill(.quaternary).frame(height: 0.5)
            }
            Text(hideWatched ? "You're all caught up" : "That's every video from your channels")
                .font(.footnote).foregroundStyle(.secondary)
            if hideWatched {
                Button("Show watched") { hideWatched = false }
                    .font(.footnote).buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct LoadingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            configuration.title.font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
