import AVKit
import SwiftUI

/// AVPlayerViewController for fullscreen, PiP and AirPlay. Detaches in background so audio keeps playing.
struct VideoSurface: UIViewControllerRepresentable {
    @Bindable var model: PlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = model.player
        vc.showsPlaybackControls = false
        vc.allowsVideoFrameAnalysis = false
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.updatesNowPlayingInfoCenter = false
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        vc.delegate = context.coordinator
        context.coordinator.attachGestures(to: vc.view)
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        let detach = model.inBackground && !model.pipActive
        if detach, vc.player != nil { vc.player = nil }
        if !detach, vc.player == nil { vc.player = model.player }
        // Back in the app while PiP is still up (e.g. stashed at the edge): close PiP and play inline.
        if model.inBackground { context.coordinator.wasInBackground = true }
        else if context.coordinator.wasInBackground {
            context.coordinator.wasInBackground = false
            if model.pipActive { context.coordinator.rebind(vc) }
        }
    }

    @MainActor final class Coordinator: NSObject, @MainActor AVPlayerViewControllerDelegate, @MainActor UIGestureRecognizerDelegate {
        let model: PlayerModel
        var wasInBackground = false
        init(model: PlayerModel) { self.model = model }

        /// YouTube-style gestures: tap shows controls, double tap left/right seeks 10 s, press and hold plays at 2x.
        func attachGestures(to view: UIView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.4
            for g in [tap, hold] as [UIGestureRecognizer] {
                g.cancelsTouchesInView = false
                g.delegate = self
                view.addGestureRecognizer(g)
            }
        }

        private var boostEnded = Date.distantPast

        @objc private func tapped(_ g: UITapGestureRecognizer) {
            guard let view = g.view, !model.boosted, Date.now.timeIntervalSince(boostEnded) > 0.3 else { return }
            model.tap(forward: g.location(in: view).x > view.bounds.midX)
        }

        @objc private func held(_ g: UILongPressGestureRecognizer) {
            switch g.state {
            case .began: model.setBoost(true)
            case .ended, .cancelled, .failed: model.setBoost(false); boostEnded = .now
            default: break
            }
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Reattaches the player to the inline view (closes PiP if it is up) without pausing playback.
        func rebind(_ vc: AVPlayerViewController, playing: Bool? = nil) {
            let wasPlaying = playing ?? (model.player.rate > 0)
            vc.player = nil
            if !model.inBackground { vc.player = model.player }
            guard wasPlaying, !model.inBackground else { return }
            model.player.play()
            // PiP teardown can pause a moment later; resume once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [model] in
                if model.player.rate == 0 { model.player.playImmediately(atRate: model.rate) }
            }
        }

        func playerViewControllerWillStartPictureInPicture(_ vc: AVPlayerViewController) {
            model.pipActive = true
        }

        private var playingAtPiPStop = false

        func playerViewControllerWillStopPictureInPicture(_ vc: AVPlayerViewController) {
            playingAtPiPStop = model.player.rate > 0
        }

        func playerViewControllerDidStopPictureInPicture(_ vc: AVPlayerViewController) {
            model.pipActive = false
            // The inline layer can stay black after PiP (e.g. when it was stashed at the edge); rebind the player.
            rebind(vc, playing: playingAtPiPStop)
        }

        func playerViewController(_ vc: AVPlayerViewController,
                                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completion: @escaping (Bool) -> Void) {
            model.isPresented = true
            completion(true)
        }
    }
}
