import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text("Capture Director")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                SelfTest.runIfRequested(model: model)
                Snapshot.runIfRequested(model: model, openSettings: openSettings)
            }
    }
}
