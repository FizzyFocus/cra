import AppKit

/// The bookmark's card (⇧⌘D, the star in the Extensions popover, Edit… on the Library's Bookmarks
/// page): the Extensions popover's own kind of window, so the two are one family to the pixel: an
/// NSPopover with the same material, the same arrow at the same place, the same spring in and out.
/// Its contents are the Extensions popover's parts: the raised action tiles along the top (Copy
/// Link, Share, Remove), bold section headers, 7 pt tiles for the name, address and folder, the
/// hairline and the footer's pills (Bookmarked, Done).
///
/// Unlike the Extensions popover it never closes by itself (`.applicationDefined`): a transient
/// one closed under the typing. It closes on Done, Remove, Escape, a click outside it, the app
/// going to the background, its window closing, the floating sidebar it hangs from going, or
/// another space coming up (MainWindowController.dismissPopovers). Changes apply as they are made,
/// as Chrome's bookmark bubble does.
@MainActor
enum BookmarkEditPopover {
    private static var current: BookmarkPopoverController?
    /// Only pages with an address of their own (not a new tab, an easel, an empty pane).
    static func canBookmark(_ url: String) -> Bool {
        guard let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return ["http", "https", "file", "chrome"].contains(scheme)
    }

    /// The card is up (in `window`, or in any window).
    static func isOpen(in window: NSWindow? = nil) -> Bool {
        guard let c = current, c.popover.isShown else { return false }
        return window.map { c.parent === $0 } ?? true
    }

    /// Shows the card for `bookmark` hanging from `anchor` (a screen rect) in `window`, as the
    /// Extensions popover hangs from its rect: under it, its arrow at the rect's middle.
    static func show(_ bookmark: Bookmark, from anchor: NSRect, in window: NSWindow, isNew: Bool) {
        current?.close(animated: false)
        guard let content = window.contentView else { return }
        let c = BookmarkPopoverController(bookmark: bookmark, isNew: isNew, parent: window)
        current = c
        c.onClosed = { [weak c] in if current === c { current = nil } }
        c.show(relativeTo: content.convert(window.convertFromScreen(anchor), from: nil), of: content)
        CraLog.note("bookmark card shows \(isNew ? "added" : "edit")")
    }

    /// Closes the card on its popover's spring (or at once); in `window` only when one is given.
    static func close(in window: NSWindow? = nil, animated: Bool = true) {
        guard let c = current, window.map({ c.parent === $0 }) ?? true else { return }
        c.close(animated: animated)
    }
}

/// One card's popover and the watch that closes it.
@MainActor
final class BookmarkPopoverController: NSObject, NSPopoverDelegate {
    let popover = NSPopover()
    weak var parent: NSWindow?
    private let card: BookmarkCardView
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    var onClosed: () -> Void = {}

    init(bookmark: Bookmark, isNew: Bool, parent: NSWindow) {
        self.parent = parent
        let dark = SystemAppearance.shared.isDark
        let icon = (NSApp.delegate as? AppDelegate)?.favicons.image(for: bookmark.url)
        card = BookmarkCardView(bookmark: bookmark, isNew: isNew, colors: SiteControlCenterColors(dark: dark), icon: icon)
        super.init()
        // The Extensions popover's own settings (SiteControlCenterPopover), but never transient.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        popover.delegate = self
        let host = NSViewController()
        host.view = card
        host.preferredContentSize = card.frame.size
        card.onResize = { [weak host, weak card] in if let card { host?.preferredContentSize = card.frame.size } }
        popover.contentViewController = host
        card.onClose = { [weak self] in self?.close(animated: true) }
    }

    func show(relativeTo rect: NSRect, of view: NSView) {
        popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
        watch()
        card.focusName()
    }

    func close(animated: Bool) {
        unwatch()
        guard popover.isShown else { return onClosed() }
        popover.animates = animated
        if animated { popover.performClose(nil) } else { popover.close() }
    }

    func popoverDidClose(_ notification: Notification) {
        unwatch()
        onClosed()
    }

    /// A click outside the card (its folder and share menus are its own), Escape (which first
    /// drops a new folder's name), the app going to the background, its window closing.
    private func watch() {
        unwatch()
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            guard let self, let mine = self.card.window else { return e }
            if e.window !== mine, e.window?.level != .popUpMenu { self.close(animated: true) }
            return e
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.keyCode == 53, let mine = self.card.window, mine.isKeyWindow else { return e }
            if !self.card.cancelNewFolder() { self.close(animated: true) }
            return nil
        } as Any)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(animated: false) }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let w = note.object as? NSWindow, w === self.parent else { return }
                self.close(animated: false)
            }
        })
    }

    private func unwatch() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

/// What the card holds, laid out on the Extensions popover's grid: 236 pt wide, 10 pt in.
final class BookmarkCardView: NSView, NSTextFieldDelegate {
    private typealias M = SiteControlCenterMetrics
    private let colors: SiteControlCenterColors
    private let bookmarkID: UUID
    private let isNew: Bool
    private let icon: NSImage?
    private let nameField = BookmarkCardField()
    private let urlField = BookmarkCardField()
    private let folderField = BookmarkCardField()
    private let folderPicker: BookmarkFolderTile
    private var makingFolder = false
    var onClose: () -> Void = {}
    var onResize: () -> Void = {}

    init(bookmark: Bookmark, isNew: Bool, colors: SiteControlCenterColors, icon: NSImage?) {
        bookmarkID = bookmark.id
        self.isNew = isNew
        self.colors = colors
        self.icon = icon
        folderPicker = BookmarkFolderTile(colors: colors)
        super.init(frame: NSRect(x: 0, y: 0, width: M.width, height: 100))
        nameField.setUp(colors: colors, placeholder: "Name", text: bookmark.title, delegate: self)
        urlField.setUp(colors: colors, placeholder: "Address", text: bookmark.url, delegate: self)
        folderField.setUp(colors: colors, placeholder: "New Folder Name", text: "", delegate: self)
        folderPicker.onPick = { [weak self] in self?.showFolderMenu() }
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private var store: BookmarkStore { .shared }
    private var bookmark: Bookmark? { store.library.bookmarks.first { $0.id == bookmarkID } }

    func focusName() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            // The popover takes the keyboard for its fields (the page had it).
            w.makeKey()
            w.makeFirstResponder(self.nameField.field)
            self.nameField.field.currentEditor()?.selectAll(nil)
        }
    }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        let x = M.inset, w = M.width - 2 * M.inset
        var y: CGFloat = 9
        // The raised buttons along the top, as the Extensions popover's.
        let url = bookmark?.url ?? ""
        let top: [(String, String, NSColor?, () -> Void)] = [
            ("link", "Copy Link", nil, { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self?.bookmark?.url ?? url, forType: .string)
                self?.onClose()
            }),
            ("square.and.arrow.up", "Share", nil, {}),
            ("trash", "Remove Bookmark", nil, { [weak self] in
                guard let self else { return }
                self.store.remove(self.bookmarkID)
                CraLog.note("bookmark removed from its card")
                self.onClose()
            }),
        ]
        for (i, (symbol, help, tint, run)) in top.enumerated() {
            let b = SiteActionButton(symbol: symbol, help: help, colors: colors, tint: tint, action: run)
            if i == 1 {
                b.onClick = { [weak self, weak b] in
                    guard let self, let b, let u = URL(string: self.bookmark?.url ?? url) else { return }
                    SharePicker.shared.show(u, relativeTo: b) { _ in }
                }
            }
            // Tiles of the Extensions row's size, spread over its full width: the first and last
            // in its first and last columns, the rest evenly between (three: columns 1, 3 and 5).
            let span = w - M.tile.width
            let left = top.count > 1 ? x + (span * CGFloat(i) / CGFloat(top.count - 1)).rounded() : x + (span / 2).rounded()
            b.frame = NSRect(x: left, y: y, width: M.tile.width, height: M.tile.height)
            addSubview(b)
        }
        y += M.tile.height + 11
        // The bookmark: its name and address in tiles under a section header.
        let page = SiteSectionView(title: isNew ? "Bookmark Added" : "Edit Bookmark", hoverText: nil, colors: colors, onHeaderClick: {})
        nameField.frame = NSRect(x: 0, y: 27, width: w, height: M.tile.height)
        urlField.frame = NSRect(x: 0, y: 27 + M.tile.height + M.gap, width: w, height: M.tile.height)
        page.addSubview(nameField)
        page.addSubview(urlField)
        let pageH = 27 + 2 * M.tile.height + M.gap
        page.frame = NSRect(x: x, y: y, width: w, height: pageH)
        addSubview(page)
        y += pageH + 15
        // Folder: the folder tile (a menu of the tree), or a new folder's name. "New Folder" shows on
        // the header under the pointer, as "Manage" does on the Extensions header.
        let folder = SiteSectionView(title: "Folder", hoverText: makingFolder ? nil : "New Folder", colors: colors) { [weak self] in
            self?.beginNewFolder()
        }
        let field: NSView = makingFolder ? folderField : folderPicker
        refreshFolder()
        field.frame = NSRect(x: 0, y: 27, width: w, height: M.tile.height)
        folder.addSubview(field)
        let folderH = 27 + M.tile.height
        folder.frame = NSRect(x: x, y: y, width: w, height: folderH)
        addSubview(folder)
        y += folderH + 13
        let divider = NSView(frame: NSRect(x: x, y: y, width: w, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = colors.divider.cgColor
        addSubview(divider)
        y += 1 + 12
        // Footer: where it is kept, and Done.
        let saved = SitePillButton(symbol: "star.fill", title: "Bookmarked", colors: colors, glyphTint: .controlAccentColor,
                                   help: "Saved in \(BookmarkStore.shared.library.path(of: bookmark?.folderId).nilIfEmpty ?? "Bookmarks")",
                                   action: nil)
        saved.frame.origin = NSPoint(x: x, y: y)
        addSubview(saved)
        let done = SitePillButton(symbol: nil, title: makingFolder ? "Add" : "Done", colors: colors, prominent: true) { [weak self] in
            guard let self else { return }
            if self.makingFolder { self.createFolder() } else { self.onClose() }
        }
        done.frame.origin = NSPoint(x: x + w - done.frame.width, y: y)
        addSubview(done)
        y += 32 + M.inset
        let size = NSSize(width: M.width, height: y)
        if frame.size != size {
            setFrameSize(size)
            onResize()
        }
    }

    // MARK: Folder

    private func refreshFolder() {
        let lib = store.library
        let id = bookmark?.folderId
        let f = lib.folder(id)
        folderPicker.show(path: lib.path(of: id).nilIfEmpty ?? "Bookmarks", color: f?.color, top: f == nil)
    }

    private func showFolderMenu() {
        let menu = NSMenu()
        let current = bookmark?.folderId
        let top = MenuItems.add(menu, "Bookmarks", on: current == nil) { [weak self] in self?.move(to: nil) }
        top.image = BookmarkFolderTile.glyph(color: nil, colors: colors, top: true)
        for entry in store.library.folderTree() {
            let f = entry.folder
            let item = MenuItems.add(menu, f.title, on: current == f.id) { [weak self] in self?.move(to: f.id) }
            item.indentationLevel = entry.depth + 1
            item.image = BookmarkFolderTile.glyph(color: f.color, colors: colors, top: false)
        }
        menu.addItem(.separator())
        MenuItems.add(menu, "New Folder…") { [weak self] in self?.beginNewFolder() }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: folderPicker.bounds.height + 4), in: folderPicker)
    }

    private func move(to folder: UUID?) {
        guard var b = bookmark, b.folderId != folder else { return }
        b.folderId = folder
        store.update(b)
        build()
    }

    private func beginNewFolder() {
        guard !makingFolder else { return }
        makingFolder = true
        folderField.field.stringValue = ""
        build()
        window?.makeFirstResponder(folderField.field)
    }

    /// Escape while a new folder's name is typed lets it go; the card stays.
    func cancelNewFolder() -> Bool {
        guard makingFolder else { return false }
        makingFolder = false
        build()
        window?.makeFirstResponder(nameField.field)
        return true
    }

    private func createFolder() {
        let name = folderField.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { _ = cancelNewFolder(); return }
        // A subfolder of the folder the bookmark is in, as Finder's New Folder makes one where you are.
        let f = store.addFolder(title: name, parentId: bookmark?.folderId)
        makingFolder = false
        move(to: f.id)
        build()
        window?.makeFirstResponder(nameField.field)
    }

    // MARK: Fields

    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f !== folderField.field, var b = bookmark else { return }
        let address = urlField.field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = nameField.field.stringValue.trimmingCharacters(in: .whitespaces)
        b.title = name.isEmpty ? address : nameField.field.stringValue
        if !address.isEmpty { b.url = address }
        store.update(b)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if control === folderField.field { createFolder() } else { onClose() }
        return true
    }

    func controlTextDidBeginEditing(_ obj: Notification) { refreshFocus(obj.object as? NSTextField) }
    func controlTextDidEndEditing(_ obj: Notification) { refreshFocus(nil) }

    private func refreshFocus(_ editing: NSTextField?) {
        for f in [nameField, urlField, folderField] { f.focused = f.field === editing }
    }
}

/// A text field in one of the popover's 7 pt tiles: the tile's fill, its hover fill while typed in.
final class BookmarkCardField: NSView {
    let field = NSTextField()
    private var colors = SiteControlCenterColors(dark: false)
    var focused = false { didSet { refresh() } }

    func setUp(colors: SiteControlCenterColors, placeholder: String, text: String, delegate: NSTextFieldDelegate) {
        self.colors = colors
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .medium)
        field.textColor = colors.text
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingTail
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: colors.secondary, .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        field.stringValue = text
        field.delegate = delegate
        field.setAccessibilityLabel(placeholder)
        if field.superview == nil { addSubview(field) }
        refresh()
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = ceil(field.intrinsicContentSize.height)
        field.frame = NSRect(x: 10, y: (bounds.height - h) / 2, width: max(0, bounds.width - 20), height: h)
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(field) }

    private func refresh() {
        layer?.backgroundColor = (focused ? colors.tileHover : colors.tile).cgColor
        layer?.borderWidth = focused ? 1 : 0
        layer?.borderColor = colors.secondary.withAlphaComponent(0.45).cgColor
    }
}

/// The folder the bookmark is in, as a tile: its glyph in the folder's colour, the folder's path
/// and the up-down chevrons; a click lists the folders.
final class BookmarkFolderTile: SiteHoverView {
    private let colors: SiteControlCenterColors
    private let glyph = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 13, weight: .medium)
    private let chevrons = NSImageView()
    var onPick: () -> Void = {}

    init(colors: SiteControlCenterColors) {
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        glyph.imageScaling = .scaleNone
        chevrons.image = SidebarSymbols.image("chevron.up.chevron.down", size: 10, weight: .semibold)
        chevrons.contentTintColor = colors.secondary
        chevrons.imageScaling = .scaleNone
        label.textColor = colors.text
        for v in [glyph, label, chevrons] { addSubview(v) }
        onClick = { [weak self] in self?.onPick() }
        setAccessibilityElement(true)
        setAccessibilityRole(.popUpButton)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(path: String, color: String?, top: Bool) {
        glyph.image = Self.glyph(color: color, colors: colors, top: top)
        label.stringValue = path
        setAccessibilityLabel("Folder: \(path)")
        needsLayout = true
    }

    /// A folder's mark in the card and its menu: the folder in its own colour, else the text's.
    static func glyph(color: String?, colors: SiteControlCenterColors, top: Bool) -> NSImage? {
        let tint = color.map { NSColor(hex: $0) } ?? colors.secondary
        return SidebarSymbols.image(top ? "bookmark.fill" : "folder.fill", size: 13)?
            .withSymbolConfiguration(.init(paletteColors: [tint]))
    }

    override func refresh() { layer?.backgroundColor = (hovered ? colors.tileHover : colors.tile).cgColor }

    override func layout() {
        super.layout()
        let h = bounds.height
        glyph.frame = NSRect(x: 10, y: 0, width: 18, height: h)
        chevrons.frame = NSRect(x: bounds.width - 24, y: 0, width: 14, height: h)
        let th = label.intrinsicContentSize.height
        label.frame = NSRect(x: 34 - SidebarText.inset, y: (h - th) / 2, width: max(0, bounds.width - 34 - 28) + 2 * SidebarText.inset, height: th)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
