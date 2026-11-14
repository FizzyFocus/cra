import Foundation

/// Pane's version of Arc Search 1.49's "Sync with Arc Desktop" (Victor's recording, 3:30): the
/// Spaces sheet before anything has synced, and the "Every tab, anywhere." card over the tab
/// row's Spaces button. Arc signs in to an Arc account; Pane has none. Upstream's iPhone app reads
/// the Mac's iCloud container, which Pane's free Apple team can't have (14 Nov 2026): the Mac syncs
/// into a folder in iCloud Drive (Settings ▸ General ▸ Sync ▸ Use a Folder…) and the phone reads
/// that folder, picked once in Files.
public enum MobileSyncIntro {
    public enum Page: Equatable { case intro, haveMac, noMac }

    public static let title = "Sync with \(Brand.name) for Mac"
    public static let body = "Search and browse your \(Brand.name) Spaces on the go."
    public static let haveMacButton = "I have \(Brand.name) on my Mac"
    public static let noMacButton = "I don\u{2019}t have \(Brand.name) yet"
    public static let goBack = "Go back"

    public static let haveMacTitle = "Sync through iCloud Drive"
    /// iCloud signed in on the phone or not.
    public static func haveMacBody(iCloud: Bool) -> String {
        let mac = "In \(Brand.name) on your Mac, open Settings \u{25B8} General \u{25B8} Sync, choose Use a Folder\u{2026} and pick a folder in "
            + "iCloud Drive. Then choose the same folder here."
        return iCloud ? mac : mac + " Sign in to iCloud on this iPhone too."
    }
    /// The button that opens Files on the folder to read the Mac's Spaces from.
    public static let chooseFolder = "Choose the Folder\u{2026}"
    public static let chooseAnotherFolder = "Choose Another Folder\u{2026}"
    /// Under the button once a folder is picked but holds no Spaces yet.
    public static func nothingIn(_ folder: String) -> String {
        "No Spaces in \u{201C}\(folder)\u{201D} yet. Your Mac\u{2019}s Sync has to use this folder, and iCloud Drive may still be bringing it over."
    }

    public static let noMacTitle = "Get \(Brand.name) on your computer first"
    public static let noMacBody = "Visit pane.uz to download \(Brand.name) for Mac."

    public static let cardTitle = "Every tab, anywhere."
    public static let cardDetail = "Sync with \(Brand.name) for Mac"

    /// The card shows over the tab row until it is closed, and never once the Mac's Spaces are here.
    public static func showsCard(hasSpaces: Bool, dismissed: Bool) -> Bool { !hasSpaces && !dismissed }
}
