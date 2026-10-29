import SwiftUI

struct MiniPlayer: View {
    @Bindable var model = PlayerModel.shared

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: model.current?.thumbnailURL) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 44, height: 28).clipShape(RoundedRectangle(cornerRadius: 5))
            Text(model.current?.title ?? "").font(.subheadline).lineLimit(1)
            Spacer(minLength: 4)
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title3)
            }
            Button { model.playNext() } label: { Image(systemName: "forward.fill") }
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture { model.isPresented = true }
    }
}
