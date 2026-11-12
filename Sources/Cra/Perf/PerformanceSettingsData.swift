import AppKit

/// Settings ▸ Performance on the settings page (cra://settings/performance, GitHub #91): what the
/// recorder measured this session, as JSON for the page. The page asks again every two seconds
/// while that section is on screen, and never while it isn't. It was the SwiftUI PerformancePane.
@MainActor
enum PerformanceSettingsData {
    /// The report read last, kept for the state the page reads in between.
    private static var latest: PerfReport?

    /// Until when the section counts as on screen: each of the page's refreshes (every 2 s while it
    /// shows) moves it on. Recording that the section started stops once it passes.
    private static var inspectingUntil: Date?
    private static let lease: TimeInterval = 6

    /// A new snapshot, then `done` (the page's state is pushed again). With recording off in
    /// Settings, the recorder runs while the section is on screen and stops a few seconds after it
    /// goes (11 Nov 2026: nothing samples in the background unless asked to).
    static func refresh(recording: Bool, done: @escaping @MainActor () -> Void) {
        let started = inspectingUntil == nil
        inspectingUntil = Date().addingTimeInterval(lease)
        if PerfRecorder.shared == nil {
            PerfRecorder.setRecording(true)
            CraLog.note("perf: recording while Settings ▸ Performance is on screen")
        }
        if started { checkLease() }
        guard let r = PerfRecorder.shared else { latest = nil; done(); return }
        r.snapshot { report in
            latest = report
            done()
        }
    }

    /// Once the section has gone (no refresh within the lease), recording goes back to the setting.
    private static func checkLease() {
        DispatchQueue.main.asyncAfter(deadline: .now() + lease + 0.5) {
            MainActor.assumeIsolated {
                guard let until = inspectingUntil else { return }
                if until > Date() { checkLease(); return }
                inspectingUntil = nil
                let setting = (NSApp.delegate as? AppDelegate)?.store.settings.perfRecording ?? false
                guard !PerfSessionRules.recording(setting: setting, environment: ProcessInfo.processInfo.environment) else { return }
                PerfRecorder.setRecording(false)
                latest = nil
                CraLog.note("perf: Settings ▸ Performance gone, recording stopped")
            }
        }
    }

    /// Copy Summary: never names a site. False while nothing is recorded.
    static func copySummary() -> Bool {
        guard let r = latest else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PerfSummary.text(r), forType: .string)
        return true
    }

    static func clear() {
        PerfRecorder.clear()
        latest = nil
    }

    static var folder: String { AppPaths.file("Perf").path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }

    /// The page's Performance section: findings, the cards of numbers, the events, newest first.
    static func json() -> [String: Any] {
        guard let r = latest else { return ["ready": false, "folder": folder] }
        func card(_ title: String, _ rows: [(String, String)]) -> [String: Any]? {
            rows.isEmpty ? nil : ["title": title, "rows": rows.map { [$0.0, $0.1] }]
        }
        let m = r.mainThread
        var cards: [[String: Any]?] = [
            card("Main thread", [
                ("Stalls of ¼ s or more", "\(m.freezes)"),
                ("Freezes of 1 s or more", "\(m.longFreezes)"),
                ("Longest freeze", m.longestFreezeMs > 0 ? PerfInsights.duration(m.longestFreezeMs) : "–"),
                ("In menus, drags, alerts, start-up", "\(m.outsideFreezes)"),
                ("Longest pass", m.longestPassMs > 0 ? PerfInsights.duration(m.longestPassMs) + (m.longestPassMode.map { " (\($0))" } ?? "") : "–"),
                ("Typical pass (99 %)", PerfInsights.duration(m.passes.percentile(0.99))),
            ]),
            card("Processes", r.processes.filter { $0.count > 0 }.map { g in
                (label(g.kind) + (g.count > 1 ? " ×\(g.count)" : ""),
                 g.available ? "\(String(format: "%.1f", g.cpuPct)) % CPU · \(PerfInsights.bytes(g.footprintBytes))" : "not available")
            }),
        ]
        if let s = r.system {
            cards.append(card("Mac", [
                ("CPU, all cores", s.cpuPct.map { "\(Int($0.rounded())) %" } ?? "–"),
                ("Memory pressure", s.memoryPressure.rawValue.capitalized),
                ("Temperature", s.thermalState.capitalized),
                ("Low Power Mode", s.lowPowerMode ? "On" : "Off"),
                ("Free disk", s.freeDiskBytes.map(PerfInsights.bytes) ?? "–"),
            ]))
        }
        cards.append(card("Tabs", tabRows(r)))
        return [
            "ready": true,
            "folder": folder,
            "insights": r.insights.map { ["title": $0.title, "detail": $0.detail, "warning": $0.severity == .warning] },
            "cards": cards.compactMap { $0 },
            "events": timeline(r).prefix(100).map { ["time": $0.time, "title": $0.title, "detail": $0.detail] },
            "footer": "Session \(r.session.id), launch \(r.session.launch), up \(Int(r.session.uptimeSeconds / 60)) min · recording costs \(String(format: "%.3f", r.selfCost.cpuPct)) % of a core",
        ]
    }

    private static func label(_ kind: PerfProcessKind) -> String {
        switch kind {
        case .browser: return "Pane"
        case .renderer: return "Pages"
        case .gpu: return "GPU"
        case .utility: return "Network, storage, audio"
        case .other: return "Other"
        }
    }

    private static func tabRows(_ r: PerfReport) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let t = r.tabs.latest { rows.append(("Tabs", "\(t.tabs) · \(t.live) loaded · \(t.slept) asleep")) }
        for (title, metric) in [("Tab switch", PerfMetric.tabSwitch), ("New page", .pageCreate), ("Page load", .pageLoad), ("Waking a slept tab", .tabWake)] {
            guard let h = r.timings[metric.rawValue], h.count > 0 else { continue }
            rows.append((title, "\(PerfInsights.duration(h.percentile(0.5))) typical · \(PerfInsights.duration(h.percentile(0.95))) slow"))
        }
        if r.tabs.longTasks > 0 { rows.append(("Busy page (long tasks)", "\(r.tabs.longTasks) · \(PerfInsights.duration(r.tabs.longTaskMs))")) }
        if r.tabs.longFrames > 0 { rows.append(("Late frames", "\(r.tabs.longFrames) · longest \(PerfInsights.duration(r.tabs.longestFrameMs))")) }
        if r.tabs.videoFrames > 0 { rows.append(("Video frames dropped", "\(r.tabs.droppedVideoFrames) of \(r.tabs.videoFrames)")) }
        return rows
    }

    private struct Row { var at: Double; var time: String; var title: String; var detail: String }

    /// Stalls and events, newest first.
    private static func timeline(_ r: PerfReport) -> [Row] {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        func time(_ at: Double) -> String { f.string(from: r.session.startedAt.addingTimeInterval(at)) }
        var rows = r.mainThread.recent.map { s in
            Row(at: s.at, time: time(s.at),
                title: "\(s.freeze ? (s.kind == .stall ? "Stall" : "Freeze") : "Busy \(s.mode) loop") \(PerfInsights.duration(s.ms))",
                detail: ([s.site].compactMap { $0 } + (s.marks.isEmpty ? [] : ["after " + s.marks.joined(separator: " → ")])).joined(separator: " · "))
        }
        rows += r.events.filter { $0.kind != "freeze" && $0.kind != "hang" }.map { e in
            Row(at: e.at, time: time(e.at), title: e.kind == "renderer" ? "Page process \(e.detail)" : "Load failed (\(e.detail))",
                detail: e.site ?? "")
        }
        return rows.sorted { $0.at > $1.at }
    }
}
