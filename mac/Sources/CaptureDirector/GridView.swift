import AppKit
import CaptureDirectorKit
import SwiftUI

/// Captures as 16:9 cards that fill the width. Every card drags out as the real video file.
struct GridView: View {
    @Environment(AppModel.self) private var model
    let entries: [LibraryEntry]

    private let columns = [GridItem(.adaptive(minimum: 208, maximum: 320), spacing: Space.lg, alignment: .top)]

    var body: some View {
        let browser = model.browser
        let order = entries.map(\.id)
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.xl) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    CaptureCard(entry: entry, selected: browser.selection.contains(entry.id))
                        .onTapGesture {
                            browser.click(entry.id, in: order, modifiers: NSEvent.modifierFlags)
                        }
                        // Alongside the click, so a single click still selects at once.
                        .simultaneousGesture(TapGesture(count: 2).onEnded { model.play(entry) })
                        .draggable(entry.fileURL)
                        .contextMenu {
                            Button("Copy video") { FileDrag.copy([entry.fileURL]) }
                        }
                        .modifier(FirstCardProbe(first: index == 0))
                }
            }
            .padding(Space.margin)
            .gridArea("grid")
        }
        // A click between cards clears the selection, like Finder.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { browser.selection = [] }
        }
    }
}

/// The first card is the grid's probe: its leading edge must sit on the page margin.
private struct FirstCardProbe: ViewModifier {
    let first: Bool
    func body(content: Content) -> some View {
        if first { content.gridProbe("first card", area: "grid") } else { content }
    }
}

/// One capture: the frame with its badge and length, then the title, date, and source site.
struct CaptureCard: View {
    @Environment(AppModel.self) private var model
    let entry: LibraryEntry
    let selected: Bool
    @State private var hovering = false
    @State private var poster: CGImage?
    /// The frame under the pointer while scrubbing; nil shows the poster.
    @State private var scrubFrame: CGImage?
    @State private var scrubTime: Double?
    @State private var scrubTask: Task<Void, Never>?
    @State private var frameWidth: CGFloat = 0

    private var frameShape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.md, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            thumbnail
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    if entry.starred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.accentText)
                            .accessibilityLabel("Starred")
                    }
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(entry.byline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.xs)
        }
        .padding(Space.xs)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onHover { on in withAnimation(Motion.hover) { hovering = on } }
        .help(entry.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var background: Color {
        if selected { return Palette.accent.opacity(0.16) }
        return hovering ? Palette.highlight : .clear
    }

    private struct PosterKey: Hashable {
        let id: String
        let changed: Date?
    }

    /// Moving the pointer across the card scrubs through the clip in quarter-second steps.
    private func scrub(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            let t = Thumbs.scrubTime(x: point.x, width: frameWidth, duration: entry.duration)
            guard t != scrubTime else { return }
            scrubTime = t
            scrubTask?.cancel()
            scrubTask = Task {
                let image = await model.thumbnails.image(for: entry, at: t)
                if !Task.isCancelled, scrubTime == t, let image { scrubFrame = image }
            }
        case .ended:
            scrubTask?.cancel()
            scrubTime = nil
            scrubFrame = nil
        }
    }

    private var thumbnail: some View {
        frameShape
            .fill(Palette.placeholder)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image = scrubFrame ?? poster {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: entry.isFinal ? "film" : "film.stack")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { frameWidth = $0 }
            .onContinuousHover { scrub($0) }
            .task(id: PosterKey(id: entry.id, changed: entry.updated)) {
                poster = await model.thumbnails.image(for: entry, at: nil)
            }
            .overlay(alignment: .topLeading) {
                KindBadge(isFinal: entry.isFinal).padding(Space.sm)
            }
            .overlay(alignment: .bottomTrailing) {
                if let d = entry.duration {
                    Text(Format.length(d))
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(Palette.onScrim)
                        .padding(.horizontal, Space.xs)
                        .padding(.vertical, 2)
                        .background(Palette.scrim, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                        .padding(Space.sm)
                }
            }
            .overlay {
                if selected {
                    frameShape.strokeBorder(Palette.accent, lineWidth: 2)
                }
            }
            .clipShape(frameShape)
    }
}

/// Final videos wear citron; clips a dark scrim, since both sit on video frames.
struct KindBadge: View {
    let isFinal: Bool

    var body: some View {
        Text(isFinal ? "Final" : "Clip")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isFinal ? Palette.onFinal : Palette.onScrim)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(isFinal ? Palette.final : Palette.scrim,
                        in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}

extension LibraryEntry {
    /// "Nov 3 · spacefast.com": the date, then the source site when there is one.
    var byline: String {
        var parts: [String] = []
        if let date = updated ?? added {
            let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
            parts.append(thisYear ? date.formatted(.dateTime.month(.abbreviated).day())
                                  : date.formatted(.dateTime.month(.abbreviated).day().year()))
        }
        if let host { parts.append(host) }
        return parts.joined(separator: " · ")
    }

    /// The source site's host, without "www.".
    var host: String? {
        guard let url, let host = URL(string: url)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
