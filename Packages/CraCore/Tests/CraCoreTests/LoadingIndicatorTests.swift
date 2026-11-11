import CoreGraphics
import CraCore
import Testing

/// Arc's loading bar (Arc 1.171 screen recording, 2 Nov 2026).
struct LoadingIndicatorTests {
    func ends(at time: Double) -> [Double] {
        let s = LoadingIndicator.sweep(at: time)
        return [s.start, s.end].map { ($0 * 100).rounded() / 100 }
    }

    /// In the 10 pt margin above the card, centred; edge to edge just inside the page's top edge
    /// rather than nowhere (it went unseen in a maximized window with the sidebar hidden, 10 Nov
    /// 2026); none over a page in full screen.
    @Test func barSitsAboveTheCardOrJustInsideIt() throws {
        let window = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let inset = CGRect(x: 300, y: 10, width: 890, height: 780)
        let above = try #require(LoadingIndicator.frame(content: inset, in: window, pageFullscreen: false))
        #expect(above == CGRect(x: 679, y: 790, width: 132, height: 10))
        let edge = try #require(LoadingIndicator.frame(content: window, in: window, pageFullscreen: false))
        #expect(edge == CGRect(x: 534, y: 790, width: 132, height: 10))
        #expect(edge.midY == window.maxY - 5, "the bar's centre 5 pt under the window's top edge, over the page")
        #expect(LoadingIndicator.frame(content: window, in: window, pageFullscreen: true) == nil)
        // A margin too thin for the bar (on the way to edge to edge) puts it inside too.
        let thin = CGRect(x: 0, y: 2, width: 1200, height: 796)
        #expect(LoadingIndicator.frame(content: thin, in: window, pageFullscreen: false)?.maxY == thin.maxY)
    }

    @Test func phaseFollowsLoadingAndCommit() {
        #expect(LoadingIndicator.Phase(isLoading: false, committed: false) == .hidden)
        #expect(LoadingIndicator.Phase(isLoading: false, committed: true) == .hidden)
        #expect(LoadingIndicator.Phase(isLoading: true, committed: false) == .waiting)
        #expect(LoadingIndicator.Phase(isLoading: true, committed: true) == .loading)
    }

    @Test func headSweepsThenTailThenGap() {
        #expect(ends(at: 0) == [0, 0])
        #expect(ends(at: 0.185) == [0, 0.5])
        #expect(ends(at: 0.37) == [0, 1])
        #expect(ends(at: 0.555) == [0.5, 1])
        #expect(ends(at: 0.9) == [1, 1])
        // The cycle repeats.
        #expect(ends(at: LoadingIndicator.sweepPeriod + 0.185) == [0, 0.5])
    }

    @Test func keyframesRunInOrderOverOneCycle() {
        for times in [LoadingIndicator.sweepKeyframes.map(\.time), LoadingIndicator.pulseKeyframes.map(\.time)] {
            #expect(times.first == 0)
            #expect(times.last == 1)
            #expect(times == times.sorted())
        }
        // A widening pill joins the sweep lit end to end.
        #expect(ends(at: LoadingIndicator.sweepTailStart * LoadingIndicator.sweepPeriod) == [0, 1])
    }
}
