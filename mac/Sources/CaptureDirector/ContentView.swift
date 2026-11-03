import CaptureDirectorKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let error = model.loadError {
                ContentUnavailableView("Couldn't read the library", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.library.entries.isEmpty && model.library.skipped == 0 {
                ContentUnavailableView("No clips yet", systemImage: "film", description: Text("Clips you record or add show up here."))
            } else {
                List(model.library.entries) { entry in
                    Label(entry.title, systemImage: "film")
                        .draggable(entry.fileURL)
                        .contextMenu {
                            Button("Copy video") { FileDrag.copy([entry.fileURL]) }
                        }
                }
                .safeAreaInset(edge: .bottom) { skippedNote }
            }
        }
        .task {
            model.load()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    @ViewBuilder private var skippedNote: some View {
        let n = model.library.skipped
        if n > 0 {
            Text(n == 1 ? "1 capture couldn't be read from library.json." : "\(n) captures couldn't be read from library.json.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }
}
