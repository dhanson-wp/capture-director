import CaptureDirectorKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    private var store: LibraryStore { model.store }

    var body: some View {
        Group {
            if let error = store.problem, store.library.entries.isEmpty {
                ContentUnavailableView("Couldn't read the library", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if store.library.entries.isEmpty && store.library.skipped == 0 {
                ContentUnavailableView("No clips yet", systemImage: "film", description: Text("Clips you record or add show up here."))
            } else {
                List(store.library.entries) { entry in
                    Label(entry.title, systemImage: "film")
                        .draggable(entry.fileURL)
                        .contextMenu {
                            Button("Copy video") { FileDrag.copy([entry.fileURL]) }
                        }
                }
                .safeAreaInset(edge: .top) { problemBanner }
                .safeAreaInset(edge: .bottom) { skippedNote }
            }
        }
        .task {
            store.start()
            SelfTest.runIfRequested(model: model)
            Snapshot.runIfRequested(model: model, openSettings: openSettings)
        }
    }

    @ViewBuilder private var problemBanner: some View {
        if let problem = store.problem {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var skippedNote: some View {
        let n = store.library.skipped
        if n > 0 {
            Text(n == 1 ? "1 capture couldn't be read from library.json." : "\(n) captures couldn't be read from library.json.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
    }
}
