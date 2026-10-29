import SwiftData
import SwiftUI

enum RootTab: Hashable { case feed, channels, search }

struct RootView: View {
    @Bindable var player = PlayerModel.shared
    @Query private var channels: [Channel]
    @State private var tab: RootTab = .feed
    @State private var didPickStartTab = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Feed", systemImage: "play.rectangle.on.rectangle", value: .feed) { FeedView() }
            Tab("Channels", systemImage: "person.2", value: .channels) { ChannelsView() }
            Tab(value: .search, role: .search) { SearchView() }
        }
        .tabViewBottomAccessory(isEnabled: player.current != nil) { MiniPlayer() }
        .tint(.red)
        .sheet(isPresented: $player.isPresented) { PlayerView() }
        .onAppear {
            guard !didPickStartTab else { return }
            didPickStartTab = true
            if channels.isEmpty { tab = .channels }
        }
    }
}
