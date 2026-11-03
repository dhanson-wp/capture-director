import AVKit
import CaptureDirectorKit
import SwiftUI

/// What the inspector shows for a selection.
enum InspectorMode: Equatable {
    case none
    case one(LibraryEntry)
    case several([LibraryEntry])

    static func of(_ entries: [LibraryEntry]) -> InspectorMode {
        switch entries.count {
        case 0: .none
        case 1: .one(entries[0])
        default: .several(entries)
        }
    }
}

/// The right panel. It reads the selection itself, so a click redraws the
/// inspector and not the window.
struct Inspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch InspectorMode.of(model.selectedEntries()) {
        case .one(let entry):
            SingleInspector(entry: entry).id(entry.id)
        case .several(let entries):
            BulkInspector(entries: entries)
        case .none:
            ContentUnavailableView("No selection", systemImage: "sidebar.trailing",
                                   description: Text("Select a capture to see its details."))
        }
    }
}

// MARK: - One capture

private struct SingleInspector: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry

    private enum Field { case title, notes }
    @FocusState private var focus: Field?
    @State private var title: String
    @State private var notes: String
    /// The last values sent to the CLI, so a commit and a focus change don't save twice.
    @State private var sentTitle: String
    @State private var sentNotes: String

    init(entry: LibraryEntry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _notes = State(initialValue: entry.notes)
        _sentTitle = State(initialValue: entry.title)
        _sentNotes = State(initialValue: entry.notes)
    }

    var body: some View {
        let exists = entry.fileExists
        Form {
            Section {
                InspectorPlayer(entry: entry)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                HStack(spacing: Space.sm) {
                    TextField("Title", text: $title, prompt: Text("Title"))
                        .labelsHidden()
                        .font(.headline)
                        .focused($focus, equals: .title)
                        .onSubmit { focus = nil; commitTitle() }
                        .onKeyPress(.escape) {
                            title = entry.title
                            focus = nil
                            return .handled
                        }
                    StarButton(starred: entry.starred) { model.toggleStar([entry]) }
                }
                LabeledContent("Kind", value: entry.isFinal ? "Final video" : "Clip")
                if let d = entry.duration { LabeledContent("Length", value: Format.length(d)) }
                if let w = entry.width, let h = entry.height { LabeledContent("Resolution", value: "\(w) × \(h)") }
                if let s = entry.size { LabeledContent("Size", value: Format.size(s)) }
            }

            Section {
                DragHandle(entries: [entry])
                ShareActions(entries: [entry], enabled: exists)
            }

            Section {
                FolderPicker(current: entry.folder) { model.move([entry], to: $0) }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 64)
                    .focused($focus, equals: .notes)
                    .accessibilityLabel("Notes")
            }

            if entry.url != nil || entry.recordAgainCommand != nil {
                Section("Source") {
                    if let site = entry.url, let link = URL(string: site) {
                        LabeledContent("Site") {
                            Link(entry.host ?? site, destination: link)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(site)
                        }
                    }
                    if let command = entry.recordAgainCommand {
                        CopyableText(label: "Record again", text: command, monospaced: true,
                                     copyHelp: "Copy the command, to paste into Terminal")
                    }
                }
            }

            Section("Location") {
                CopyableText(label: nil, text: entry.file, monospaced: false, copyHelp: "Copy the full path")
            }
        }
        .formStyle(.grouped)
        .onChange(of: focus) { old, new in
            model.browser.editingText = new != nil
            if old == .title, new != .title { commitTitle() }
            if old == .notes, new != .notes { saveNotes() }
        }
        // Notes save themselves once typing pauses.
        .task(id: notes) {
            try? await Task.sleep(for: Pause.notes)
            if !Task.isCancelled { saveNotes() }
        }
        // A change from elsewhere (the CLI, another window) shows unless it's being edited.
        .onChange(of: entry.title) { _, new in
            sentTitle = new
            if focus != .title { title = new }
        }
        .onChange(of: entry.notes) { _, new in
            sentNotes = new
            if focus != .notes { notes = new }
        }
        .onDisappear {
            commitTitle()
            saveNotes()
            model.browser.editingText = false
        }
    }

    private func commitTitle() {
        let words = title.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            title = entry.title
            return
        }
        let clean = words.joined(separator: " ")
        title = clean
        guard clean != sentTitle else { return }
        sentTitle = clean
        let store = model.store, id = entry.id
        Task { await store.setTitle(id, clean) }
    }

    private func saveNotes() {
        guard notes != sentNotes else { return }
        sentNotes = notes
        let store = model.store, id = entry.id, text = notes
        Task { await store.setNotes(id, text) }
    }
}

/// The video, paused, ready to play in place.
private struct InspectorPlayer: View {
    let entry: LibraryEntry
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Palette.placeholder
            if let player {
                VideoPlayer(player: player)
            } else if !entry.fileExists {
                VStack(spacing: Space.xs) {
                    Image(systemName: "questionmark.folder")
                        .font(.title2)
                    Text("File moved")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .task(id: entry.file) {
            player = entry.fileExists ? AVPlayer(url: entry.fileURL) : nil
        }
        .onDisappear { player?.pause() }
    }

    private var aspect: CGFloat {
        guard let w = entry.width, let h = entry.height, w > 0, h > 0 else { return 16 / 9 }
        return CGFloat(w) / CGFloat(h)
    }
}

// MARK: - Several captures

private struct BulkInspector: View {
    @Environment(AppModel.self) private var model
    let entries: [LibraryEntry]

    var body: some View {
        let starAll = Bulk.starTarget(entries)
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\(entries.count) captures")
                        .font(.title3.weight(.semibold))
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Space.xs)
            }

            Section {
                DragHandle(entries: entries)
                ShareActions(entries: entries, enabled: entries.contains(where: \.fileExists))
            }

            Section {
                FolderPicker(current: Set(entries.map(\.folder)).count == 1 ? entries[0].folder : nil) {
                    model.move(entries, to: $0)
                }
                Button(starAll ? "Star all" : "Unstar all",
                       systemImage: starAll ? "star" : "star.slash") { model.toggleStar(entries) }
                    .foregroundStyle(Color.primary)
                    .help(starAll ? "Star every selected capture (Shift-Command-L)"
                                  : "Unstar every selected capture (Shift-Command-L)")
                Button("Remove from library…", systemImage: "minus.circle", role: .destructive) {
                    model.browser.removeSelected?()
                }
                .foregroundStyle(.red)
                .help("Forget these captures. The video files stay where they are (Command-Delete).")
            }
        }
        .formStyle(.grouped)
    }

    /// "1:18 in all · 4.2 MB", leaving out what isn't known.
    private var summary: String {
        var parts: [String] = []
        let lengths = entries.compactMap(\.duration)
        if !lengths.isEmpty { parts.append("\(Format.length(lengths.reduce(0, +))) in all") }
        let sizes = entries.compactMap(\.size)
        if !sizes.isEmpty { parts.append(Format.size(sizes.reduce(0, +))) }
        let finals = entries.filter(\.isFinal).count
        parts.append(finals == 0 ? "all clips" : finals == entries.count ? "all final videos"
                     : "\(finals) final, \(entries.count - finals) clips")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Shared pieces

private struct StarButton: View {
    let starred: Bool
    let action: () -> Void

    var body: some View {
        Button(starred ? "Unstar" : "Star", systemImage: starred ? "star.fill" : "star", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(starred ? AnyShapeStyle(Palette.accentText) : AnyShapeStyle(.secondary))
            .help(starred ? "Unstar (Shift-Command-L)" : "Star (Shift-Command-L)")
    }
}

/// The big target: drag it into a browser upload box, Slack, or Finder to drop the real files.
struct DragHandle: View {
    let entries: [LibraryEntry]

    var body: some View {
        let files = entries.filter(\.fileExists)
        HStack(spacing: Space.md) {
            Image(systemName: entries.count > 1 ? "film.stack" : "film")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: Space.section)
            VStack(alignment: .leading, spacing: 2) {
                Text("Drag into any upload page")
                    .font(.headline)
                Text(detail(files))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(Space.md)
        .background(Palette.highlight.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .fileDrag(files)
        .opacity(files.isEmpty ? 0.5 : 1)
        .help(files.isEmpty ? "The video isn't at its path anymore"
                            : "Drag the video files into a browser, Slack, or Finder")
        .accessibilityElement(children: .combine)
    }

    private func detail(_ files: [LibraryEntry]) -> String {
        if files.isEmpty { return entries.count == 1 ? "File moved" : "Files moved" }
        if entries.count == 1 { return files[0].fileURL.lastPathComponent }
        let gone = entries.count - files.count
        return gone == 0 ? "\(files.count) videos" : "\(files.count) videos, \(gone) moved"
    }
}

/// Share, Copy video, Show in Finder, and Copy for agent.
private struct ShareActions: View {
    @Environment(AppModel.self) private var model
    let entries: [LibraryEntry]
    let enabled: Bool

    var body: some View {
        let urls = entries.filter(\.fileExists).map(\.fileURL)
        Grid(horizontalSpacing: Space.sm, verticalSpacing: Space.sm) {
            GridRow {
                ShareLink(items: urls) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .disabled(!enabled)
                .help("Send the video with AirDrop, Mail, Messages, and more")
                Button {
                    model.copyVideos(entries)
                } label: {
                    Label("Copy video", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .disabled(!enabled)
                .help("Copy the video file, to paste into Slack or Finder (Option-Command-C)")
            }
            GridRow {
                Button {
                    model.showInFinder(entries)
                } label: {
                    Label("Show in Finder", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .disabled(!enabled)
                .help("Show the video in Finder (Shift-Command-R)")
                Button {
                    model.copyForAgent(entries)
                } label: {
                    Label("Copy for agent", systemImage: "terminal").frame(maxWidth: .infinity)
                }
                .help("Copy the path, length, and shot list as text for a coding agent (Shift-Command-C)")
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(StackedLabel())
        .lineLimit(1)
    }
}

/// Icon over title, so four actions fit two by two in a narrow inspector.
private struct StackedLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: Space.xs) {
            configuration.icon.font(.title3)
            configuration.title.font(.callout)
        }
        // Label color, not the tint: mid mulberry on a gray dark-mode fill reads as disabled.
        .foregroundStyle(Color.primary)
        .padding(.vertical, Space.xs)
    }
}

/// Unsorted, every folder, and New folder…, for one capture or several.
private struct FolderPicker: View {
    @Environment(AppModel.self) private var model
    /// The folder the captures share; nil when they're in different folders.
    let current: String?
    let pick: (String) -> Void
    @State private var naming = false
    @State private var name = ""

    private static let newTag = "\u{0}new"
    private static let mixedTag = "\u{0}mixed"

    var body: some View {
        let paths = FolderTree.paths(model.store.library)
        // Several captures in different folders show "Several folders" until one is picked.
        let shown = current ?? Self.mixedTag
        Picker(current == nil ? "Move to folder" : "Project",
               selection: Binding(get: { shown }, set: { choose($0) })) {
            if current == nil { Text("Several folders").tag(Self.mixedTag) }
            Text("Unsorted").tag("")
            if !paths.isEmpty { Divider() }
            ForEach(paths, id: \.self) { Text($0).tag($0) }
            Divider()
            Text("New folder…").tag(Self.newTag)
        }
        .help(current == nil ? "Move every selected capture into a folder" : "Move this capture into a folder")
        .alert("New folder", isPresented: $naming) {
            TextField("Folder name", text: $name)
            Button("Create and move") {
                let path = FolderPath.normalize(name)
                if !path.isEmpty { pick(path) }
                name = ""
            }
            Button("Cancel", role: .cancel) { name = "" }
        } message: {
            Text("Use a slash to put it inside another folder, like blog/Launch.")
        }
        // Space and Command-Delete stay with the text field while the alert is up.
        .onChange(of: naming) { _, on in model.browser.editingText = on }
    }

    private func choose(_ value: String) {
        if value == Self.newTag { naming = true } else if value != Self.mixedTag, value != current { pick(value) }
    }
}

/// A line people may want to paste somewhere, with a copy button.
private struct CopyableText: View {
    let label: String?
    let text: String
    let monospaced: Bool
    let copyHelp: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let label {
                Text(label)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.sm) {
                Text(text)
                    .font(monospaced ? .callout.monospaced() : .callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copy", systemImage: "doc.on.doc") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(text, forType: .string)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(copyHelp)
            }
        }
    }
}
