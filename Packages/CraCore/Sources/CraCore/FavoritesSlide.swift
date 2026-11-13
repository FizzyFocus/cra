import Foundation

/// The favorites over the space pager while it moves (13 Nov 2026, the owner's call). There is one
/// grid per window, outside the pager. Between spaces that share a favorites list (one profile,
/// AppSettings.sharedFavorites) it stays still. A space with a list of its own (another profile, or
/// sharing off) brings its list in with its page: each list in sight rides at its page's place, the
/// same distance the tabs travel, under the fingers and on the settle spring alike.
public enum FavoritesSlide {
    public struct Placement: Equatable {
        /// Where the grid's own list sits, in page widths from its resting place; nil while no page
        /// in sight uses it (a jump across several spaces).
        public var shown: Double?
        /// Other lists in sight: the page each rides with and where, in page widths.
        public var others: [Other]

        public init(shown: Double?, others: [Other]) {
            self.shown = shown
            self.others = others
        }

        /// At rest: the grid's own list in its place and nothing beside it.
        public var isAtRest: Bool { shown == 0 && others.isEmpty }
    }

    public struct Other: Equatable {
        public var page: Int
        public var x: Double

        public init(page: Int, x: Double) {
            self.page = page
            self.x = x
        }
    }

    /// `position` is where the pager shows, in pages (2.25 is a quarter of the way from the third
    /// space to the fourth); `lists[i]` is page i's favorites list; `shown` is the list the grid
    /// has up. Past either end (the pull that opens Create a Space) the favorites stay put.
    public static func place<List: Equatable>(position: Double, lists: [List], shown: List?) -> Placement {
        guard !lists.isEmpty, position.isFinite else { return Placement(shown: 0, others: []) }
        let p = min(max(position, 0), Double(lists.count - 1))
        let a = Int(p.rounded(.down)), b = Int(p.rounded(.up))
        // The pages in sight: one list over both stays still; two lists each ride with their page.
        let spans: [(list: List, page: Int, x: Double)] = a == b || lists[a] == lists[b]
            ? [(lists[a], abs(Double(a) - p) <= abs(Double(b) - p) ? a : b, 0)]
            : [(lists[a], a, Double(a) - p), (lists[b], b, Double(b) - p)]
        var out = Placement(shown: nil, others: [])
        for s in spans {
            if out.shown == nil, s.list == shown { out.shown = s.x } else { out.others.append(Other(page: s.page, x: s.x)) }
        }
        return out
    }
}
