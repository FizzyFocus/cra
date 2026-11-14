import CraCore
import UIKit

/// Links saved through the share extension ("Saved" in other apps' share sheets) wait in the
/// inbox (a Keychain item the app and the extension both claim on Pane's free Apple team, which has
/// no App Groups); the browser takes them whenever it comes to the front.
extension BrowserViewController {
    /// `-CraFakeShare <url>`: a test puts a link in the inbox as the extension would, in the real
    /// Keychain item, before the browser looks.
    static func saveFakeShareForTest() {
        guard let url = LaunchOptions.value("CraFakeShare") else { return }
        let place = MobileShareInbox.Destination(rawValue: LaunchOptions.value("CraFakeShareTo") ?? "") ?? .tabs
        MobileShareInbox.updateInKeychain { (inbox: inout MobileShareInbox) in
            inbox.save(url: url, title: "Shared page", to: place, at: Date())
        }
    }

    func takeSharedLinks() {
        let links = MobileShareInbox.updateInKeychain { (inbox: inout MobileShareInbox) in inbox.take() }
        guard !links.isEmpty else { return }
        for link in links {
            switch link.destination {
            case .tabs: store.add(url: link.url, title: link.title)
            case .favorites: favorites.add(url: link.url, title: link.title)
            }
        }
        refreshTabStack()
        if isSearching, sheet.text.isEmpty {
            sheet.setFavorites(favorites.value.shown().map { ($0, favicons.icon(for: $0.url)) })
        }
    }
}
