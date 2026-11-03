import CaptureDirectorKit
import SwiftUI

/// Captures as a table, the faster view for a big library. Click a column
/// header to sort by it; choosing an order in the toolbar's Sort menu goes
/// back to that order. Every row drags out as the real video file.
struct ListView: View {
    @Environment(AppModel.self) private var model
    let entries: [LibraryEntry]
    @State private var columnSort: [KeyPathComparator<LibraryEntry>] = []

    var body: some View {
        @Bindable var browser = model.browser
        let rows = columnSort.isEmpty ? entries : entries.sorted(using: columnSort)
        Table(of: LibraryEntry.self, selection: $browser.selection, sortOrder: $columnSort) {
            TableColumn("Title", value: \.title) { entry in
                HStack(spacing: Space.xs) {
                    Text(entry.title).lineLimit(1).help(entry.title)
                    if entry.starred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.accentText)
                            .accessibilityLabel("Starred")
                    }
                }
            }
            .width(min: 160, ideal: 220)
            TableColumn("Project", value: \.projectName) { entry in
                Text(entry.projectName).lineLimit(1).help(entry.projectName)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Kind", value: \.kindName) { entry in
                KindBadge(isFinal: entry.isFinal)
            }
            .width(min: 52, ideal: 60, max: 72)
            TableColumn("Length", value: \.lengthValue) { entry in
                Text(entry.duration.map(Format.length) ?? "")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 60, max: 80)
            TableColumn("Date", value: \.dateValue) { entry in
                Text((entry.updated ?? entry.added).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
                    .monospacedDigit()
            }
            .width(min: 88, ideal: 104)
            TableColumn("Size", value: \.sizeValue) { entry in
                Text(entry.size.map(Format.size) ?? "")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 72, max: 96)
            TableColumn("Location", value: \.location) { entry in
                Text(entry.location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.file)
            }
            .width(min: 120, ideal: 240)
        } rows: {
            ForEach(rows) { entry in
                TableRow(entry)
                    .draggable(entry.fileURL)
            }
        }
        .contextMenu(forSelectionType: LibraryEntry.ID.self) { ids in
            let urls = rows.filter { ids.contains($0.id) }.map(\.fileURL)
            if !urls.isEmpty {
                Button("Copy video") { FileDrag.copy(urls) }
            }
        }
        .onChange(of: browser.sort) { columnSort = [] }
    }
}

/// Sort keys for the table's columns. A missing value sorts first going up.
extension LibraryEntry {
    var projectName: String { folder.isEmpty ? "Unsorted" : folder }
    var kindName: String { isFinal ? "Final" : "Clip" }
    var lengthValue: Double { duration ?? -1 }
    var dateValue: Date { updated ?? added ?? .distantPast }
    var sizeValue: Int { size ?? -1 }
    /// The folder the video is in, with ~ for the home folder.
    var location: String {
        (((file as NSString).deletingLastPathComponent) as NSString).abbreviatingWithTildeInPath
    }
}
