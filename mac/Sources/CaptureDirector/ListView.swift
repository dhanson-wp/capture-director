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
        // With several rows selected, a selected row's cells start one drag of them all.
        let selected = rows.filter { browser.selection.contains($0.id) }
        let multi = selected.count > 1 ? selected : nil
        let cell = { (entry: LibraryEntry) -> [LibraryEntry]? in
            browser.selection.contains(entry.id) ? multi : nil
        }
        Table(of: LibraryEntry.self, selection: $browser.selection, sortOrder: $columnSort) {
            TableColumn("Title", value: \.title) { entry in
                HStack(spacing: Space.sm) {
                    RowPoster(entry: entry)
                    Text(entry.title).lineLimit(1).help(entry.title)
                    if entry.starred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.accentText)
                            .accessibilityLabel("Starred")
                    }
                }
                .rowDrag(cell(entry))
            }
            .width(min: 160, ideal: 220)
            TableColumn("Project", value: \.projectName) { entry in
                Text(entry.projectName).lineLimit(1).help(entry.projectName)
                    .rowDrag(cell(entry))
            }
            .width(min: 100, ideal: 140)
            TableColumn("Kind", value: \.kindName) { entry in
                KindBadge(isFinal: entry.isFinal)
                    .rowDrag(cell(entry))
            }
            .width(min: 52, ideal: 60, max: 72)
            TableColumn("Length", value: \.lengthValue) { entry in
                Text(entry.duration.map(Format.length) ?? "")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .rowDrag(cell(entry))
            }
            .width(min: 52, ideal: 60, max: 80)
            TableColumn("Date", value: \.dateValue) { entry in
                Text((entry.updated ?? entry.added).map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "")
                    .monospacedDigit()
                    .rowDrag(cell(entry))
            }
            .width(min: 88, ideal: 104)
            TableColumn("Size", value: \.sizeValue) { entry in
                Text(entry.size.map(Format.size) ?? "")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .rowDrag(cell(entry))
            }
            .width(min: 60, ideal: 72, max: 96)
            TableColumn("Location", value: \.location) { entry in
                Text(entry.location)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.file)
                    .rowDrag(cell(entry))
            }
            .width(min: 120, ideal: 240)
        } rows: {
            ForEach(rows) { entry in
                // SwiftUI's row drag carries one file; several selected rows drag from their cells instead.
                if cell(entry) == nil {
                    TableRow(entry)
                        .draggable(entry.fileURL)
                } else {
                    TableRow(entry)
                }
            }
        }
        .contextMenu(forSelectionType: LibraryEntry.ID.self) { ids in
            let picked = rows.filter { ids.contains($0.id) }
            if !picked.isEmpty { CaptureMenuItems(entries: picked) }
        } primaryAction: { ids in
            // Double-click, or Return, on a row.
            if ids.count == 1, let entry = rows.first(where: { ids.contains($0.id) }) { model.play(entry) }
        }
        .onChange(of: browser.sort) { columnSort = [] }
    }
}

private extension View {
    /// A cell of a selected row while several are selected: the whole cell drags them all.
    /// The gesture stays attached and switches off, so the cell keeps its state.
    func rowDrag(_ entries: [LibraryEntry]?) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .modifier(MultiFileDrag(entries: entries ?? [], enabled: entries != nil))
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

/// The poster frame at the start of a row, small. Loads when the row scrolls into view.
private struct RowPoster: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry
    @State private var poster: CGImage?

    private struct PosterKey: Hashable {
        let id: String
        let changed: Date?
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.xs, style: .continuous) }

    var body: some View {
        shape
            .fill(Palette.placeholder)
            .overlay {
                if let poster {
                    Image(decorative: poster, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .clipShape(shape)
            .frame(width: 48, height: 28)
            .accessibilityHidden(true)
            .task(id: PosterKey(id: entry.id, changed: entry.updated)) {
                let image = await model.thumbnails.image(for: entry, at: nil)
                if !Task.isCancelled { poster = image }
            }
    }
}
