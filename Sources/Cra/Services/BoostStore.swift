import Foundation
import Observation

/// Every Boost (Arc's per-site restyles), in boosts.json in the data folder.
@MainActor
@Observable
final class BoostStore {
    static let shared = BoostStore()
    @ObservationIgnored private let file = JSONStore<[Boost]>("boosts.json")
    private(set) var boosts: [Boost]

    private init() { boosts = file.load(or: { [] }) }

    func boost(_ id: UUID) -> Boost? { boosts.first { $0.id == id } }

    /// A site's boosts, oldest first: all of those on apply together, in that order (13 Nov 2026).
    func boosts(forHost host: String) -> [Boost] { boosts.filter { $0.host == Boost.siteHost(host) } }

    /// The site's boost to edit: the one opened last, else its newest.
    func boost(forHost host: String) -> Boost? {
        let mine = boosts(forHost: host)
        return mine.first { $0.id == lastOpened[Boost.siteHost(host)] } ?? mine.last
    }

    /// The boost the editor opened last on each site (this run).
    @ObservationIgnored private var lastOpened: [String: UUID] = [:]
    func noteOpened(_ b: Boost) { lastOpened[b.host] = b.id }

    /// The site's boost to edit, made when it has none (the Site Control Center's Boost).
    func boostForSite(of url: String) -> Boost? {
        guard let host = URL(string: url)?.host, url.hasPrefix("http") else { return nil }
        return boost(forHost: host) ?? newBoost(host: host)
    }

    /// New Boost: another boost for the site, beside the ones it has ("My Boost 2").
    func newBoost(forSite url: String) -> Boost? {
        guard let host = URL(string: url)?.host, url.hasPrefix("http") else { return nil }
        return newBoost(host: host)
    }

    @discardableResult
    func newBoost(host: String) -> Boost {
        let b = Boost(host: host, name: Boost.nextName(taken: boosts(forHost: host).map(\.name)))
        boosts.append(b)
        file.save(boosts)
        BoostStore.changed?(b.host)
        return b
    }

    func update(_ boost: Boost) {
        guard let i = boosts.firstIndex(where: { $0.id == boost.id }) else { return }
        boosts[i] = boost
        file.save(boosts)
        BoostStore.changed?(boost.host)
    }

    func delete(_ id: UUID) {
        let host = boost(id)?.host
        boosts.removeAll { $0.id == id }
        file.save(boosts)
        if let host { BoostStore.changed?(host) }
    }

    /// The pages on a host get their boost again (set by the app: BrowserManager re-applies).
    @ObservationIgnored static var changed: ((String) -> Void)?
}
