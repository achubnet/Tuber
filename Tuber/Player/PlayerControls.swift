import SwiftUI

/// Rounded play triangle from the app icon.
struct PlayGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = w * 0.12
        let a = CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.1)
        let b = CGPoint(x: rect.minX + w * 0.2, y: rect.minY + h * 0.9)
        let c = CGPoint(x: rect.minX + w * 0.92, y: rect.midY)
        var p = Path()
        p.move(to: CGPoint(x: a.x, y: rect.midY))
        p.addArc(tangent1End: b, tangent2End: c, radius: r)
        p.addArc(tangent1End: c, tangent2End: a, radius: r)
        p.addArc(tangent1End: a, tangent2End: b, radius: r)
        p.closeSubpath()
        return p
    }
}

/// Play/pause in the icon style: white over video, red elsewhere.
struct PlayPauseGlyph: View {
    var isPlaying: Bool
    var onVideo = false

    private var fill: LinearGradient {
        onVideo
            ? LinearGradient(colors: [.white, .white.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color(red: 1, green: 0.36, blue: 0.27), Color(red: 0.76, green: 0.05, blue: 0.2)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            Group {
                if isPlaying {
                    HStack(spacing: s * 0.18) {
                        RoundedRectangle(cornerRadius: s * 0.08).fill(fill).frame(width: s * 0.24)
                        RoundedRectangle(cornerRadius: s * 0.08).fill(fill).frame(width: s * 0.24)
                    }
                    .padding(.vertical, s * 0.12)
                    .frame(width: s, height: s)
                } else {
                    PlayGlyph().fill(fill)
                }
            }
            .shadow(color: onVideo ? .black.opacity(0.35) : .red.opacity(0.3), radius: s * 0.08, y: s * 0.03)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.15), value: isPlaying)
    }
}

/// Controls drawn over the video: tap toggles them, double tap seeks.
struct VideoOverlay: View {
    @Bindable var model: PlayerModel
    var fullscreen: Bool

    var body: some View {
        ZStack {
            if model.controlsVisible, !model.isLoading, model.error == nil {
                // While controls are up this layer gets the touches, so taps on the video are handled here too.
                GeometryReader { geo in
                    Color.black.opacity(fullscreen ? 0.4 : 0.3)
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { model.tap(forward: $0.location.x > geo.size.width / 2) })
                }
                Button { model.togglePlay() } label: {
                    PlayPauseGlyph(isPlaying: model.isPlaying, onVideo: true)
                        .frame(width: 54, height: 54).padding(20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                if fullscreen {
                    FullscreenBar(model: model)
                } else {
                    fullscreenButton.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            if let burst = model.seekBurst { SeekRipple(burst: burst).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.2), value: model.controlsVisible)
        .animation(.easeOut(duration: 0.2), value: model.seekBurst)
    }

    private var fullscreenButton: some View {
        Button { Orientation.set(landscape: !fullscreen) } label: {
            Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.body.weight(.semibold)).foregroundStyle(.white)
                .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Full screen")
    }
}

/// Landscape controls: title on top, seek bar and buttons at the bottom.
private struct FullscreenBar: View {
    @Bindable var model: PlayerModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.current?.title ?? "")
                .font(.headline).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 14)
                .allowsHitTesting(false)
            Spacer()
            HStack(spacing: 6) {
                Menu {
                    Picker("Playback speed", selection: Binding(get: { model.rate }, set: { model.setRate($0) })) {
                        ForEach(PlayerModel.rates.reversed(), id: \.self) { r in
                            Text(r == 1 ? String(localized: "Normal") : String(format: "%g×", r)).tag(r)
                        }
                    }
                } label: { chip(Text(verbatim: String(format: "%g×", model.rate))) }
                if model.audioOptions.count > 1 {
                    Menu {
                        Picker("Audio track", selection: Binding(get: { model.audioOption },
                                                                 set: { if let o = $0 { model.selectAudio(o) } })) {
                            ForEach(model.audioOptions, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                        }
                    } label: { chip(Image(systemName: "waveform")) }
                    .accessibilityLabel("Audio track")
                }
                Spacer()
                Button { model.playNext() } label: { chip(Image(systemName: "forward.end.fill")) }
                    .accessibilityLabel("Next")
                Button { Orientation.set(landscape: false) } label: { chip(Image(systemName: "arrow.down.right.and.arrow.up.left")) }
                    .accessibilityLabel("Full screen")
            }
            .menuStyle(.button).menuIndicator(.hidden)
            .buttonStyle(.plain)
            SegmentBar(model: model).padding(.top, 2)
        }
        .padding(.horizontal, 20).padding(.bottom, 10)
        .environment(\.colorScheme, .dark)
    }

    private func chip(_ content: some View) -> some View {
        content.font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .frame(minWidth: 40, minHeight: 36).padding(.horizontal, 4)
            .contentShape(Rectangle())
    }
}

/// Half-circle on the tapped side with the seconds skipped, like YouTube.
struct SeekRipple: View {
    let burst: PlayerModel.SeekBurst

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * 0.38, h = geo.size.height
            ZStack {
                Ellipse().fill(.white.opacity(0.18))
                    .frame(width: w * 2, height: h * 1.5)
                    .offset(x: burst.forward ? w / 2 : -w / 2)
                VStack(spacing: 6) {
                    HStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { _ in Image(systemName: "arrowtriangle.right.fill") }
                    }
                    .font(.system(size: 11))
                    .scaleEffect(x: burst.forward ? 1 : -1)
                    Text("\(burst.seconds) sec").font(.footnote.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(.white)
            }
            .frame(width: w, height: h)
            .clipped()
            .frame(maxWidth: .infinity, alignment: burst.forward ? .trailing : .leading)
        }
        .allowsHitTesting(false)
    }
}

/// Hosts SwiftUI above a UIKit view so its controls get touches; while inactive, touches go to the view below.
struct PassthroughHost<Content: View>: UIViewRepresentable {
    var isActive: () -> Bool
    @ViewBuilder var content: Content

    func makeUIView(context: Context) -> Container {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.sizingOptions = []
        let v = Container()
        v.host = host
        v.isActive = isActive
        host.view.frame = v.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.addSubview(host.view)
        return v
    }

    func updateUIView(_ v: Container, context: Context) { v.host?.rootView = content }

    final class Container: UIView {
        var host: UIHostingController<Content>?
        var isActive: () -> Bool = { true }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            isActive() ? super.hitTest(point, with: event) : nil
        }
    }
}

@MainActor enum Orientation {
    static func set(landscape: Bool) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait))
    }
}
