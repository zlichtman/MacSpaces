import Foundation

/// Where an arrow key goes in a grid of `count` items read left to right, `columns` across: left
/// and right run on through the rows, up and down keep the column. Nil when there's nowhere to go.
/// Down from a short last row's neighbour lands on the last item, so nothing is out of reach.
enum GridMove {
    enum Direction { case left, right, up, down }

    static func target(from index: Int?, count: Int, columns: Int, _ direction: Direction) -> Int? {
        guard count > 0, columns > 0 else { return nil }
        guard let index, (0..<count).contains(index) else { return 0 }
        switch direction {
        case .left: return index > 0 ? index - 1 : nil
        case .right: return index + 1 < count ? index + 1 : nil
        case .up: return index >= columns ? index - columns : nil
        case .down:
            if index + columns < count { return index + columns }
            let lastRow = (count - 1) / columns
            return index / columns < lastRow ? count - 1 : nil
        }
    }
}
