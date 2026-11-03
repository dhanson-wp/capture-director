import Foundation

/// Where an arrow key goes in a grid of cards laid out row by row, like Finder's icon view.
public enum GridMove {
    public enum Direction: Sendable {
        case left, right, up, down, home, end
    }

    /// How many columns an adaptive grid fits: as many `minimum`-wide cards, with
    /// `spacing` between them, as fit in `width`. Never fewer than one.
    public static func columns(width: Double, minimum: Double, spacing: Double) -> Int {
        guard width.isFinite, minimum > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    /// The index an arrow moves to from `index` among `count` cards in `columns` columns,
    /// or nil when there are no cards. With nothing to start from, Down, Right, and Home
    /// go to the first card, and Up, Left, and End to the last. Left and Right run on
    /// across rows; Up and Down keep the column, and Down from above a short last row
    /// lands on the last card. At an edge it stays put.
    public static func next(from index: Int?, _ direction: Direction, count: Int, columns: Int) -> Int? {
        guard count > 0 else { return nil }
        let columns = max(1, columns)
        guard let index, index >= 0, index < count else {
            switch direction {
            case .down, .right, .home: return 0
            case .up, .left, .end: return count - 1
            }
        }
        switch direction {
        case .left: return max(0, index - 1)
        case .right: return min(count - 1, index + 1)
        case .up: return index - columns >= 0 ? index - columns : index
        case .down:
            if index + columns < count { return index + columns }
            // A row below exists but is too short for this column.
            let lastRow = (count - 1) / columns
            return index / columns < lastRow ? count - 1 : index
        case .home: return 0
        case .end: return count - 1
        }
    }
}
