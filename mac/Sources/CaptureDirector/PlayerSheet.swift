import AVKit
import CaptureDirectorKit
import SwiftUI

/// Double-click on a capture: the video in a sheet, playing.
struct PlayerSheet: View {
    let entry: LibraryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(entry: LibraryEntry) {
        self.entry = entry
        _player = State(initialValue: AVPlayer(url: entry.fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .aspectRatio(aspect, contentMode: .fit)
                .frame(minWidth: 640, idealWidth: 880, minHeight: 360)
            HStack {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("player.close")
            }
            .padding(Space.md)
        }
        .noInitialFocus()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player")
        .onAppear { player.play() }
        .onDisappear { player.pause() }
    }

    private var aspect: CGFloat {
        guard let w = entry.width, let h = entry.height, w > 0, h > 0 else { return 16 / 9 }
        return CGFloat(w) / CGFloat(h)
    }
}
