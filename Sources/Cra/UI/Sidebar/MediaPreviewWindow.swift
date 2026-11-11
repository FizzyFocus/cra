import AVKit
import AppKit
import CoreImage
import QuickLookUI
import WebKit

/// Arc's preview for a picture or video picked in Library ▸ Media (MediaPreviewWindow, Arc 1.172.1;
/// CraCore MediaPreview has the measurements): a panel over the dimmed window that grows out of the
/// picked thumbnail, the Library and the space left as they were. ✕, Esc or a click on the dimmed
/// window closes it; ‹ › and the arrow keys step through the grid; ⋯ has the file's menu and "Open
/// in Preview" hands it to the Mac's app for it.
///
/// Since 11 Nov 2026 a download picked in the tray over the Library button or on Library ▸ Downloads
/// opens here too (before, it opened in its app): pictures and videos as in Media, documents (PDF,
/// text, Office and iWork files, sound) in Quick Look's view, WebM in a web view. What it can't show
/// (an archive, a disk image) still opens in its app (CraCore MediaPreview.kind).
@MainActor
final class MediaPreviewController {
    static let shared = MediaPreviewController()
    /// A file was hidden from the preview: the grid reads again.
    static let hidden = Notification.Name("CraMediaHidden")
    /// cra://debug?previewSlow: the overlay's animations at this speed (stills of the grow).
    static var debugSpeed: Float = 1
    /// Where the files came from: what ⋯ offers (Media's menu, or a download's).
    enum Source: String { case media, downloads, webImage }
    private var overlay: MediaPreviewOverlay?

    var isShown: Bool { overlay != nil }

    /// `thumbnail` is where the picked picture is drawn, in screen points. `window` may be the
    /// floating sidebar's panel: the preview covers the browser window it belongs to. `origin` says
    /// where a file's thumbnail is now in the list it came from (screen points), for the panel to
    /// shrink back into on closing, whichever file it shows by then; `onClose` hears it start closing.
    func show(_ files: [MediaLibrary.File], at index: Int, from thumbnail: NSRect?, over window: NSWindow, source: Source = .media,
              address: String? = nil, origin: ((String) -> NSRect?)? = nil, onClose: (() -> Void)? = nil) {
        guard files.indices.contains(index) else { return }
        overlay?.close(animated: false)
        let o = MediaPreviewOverlay(parent: Self.browserWindow(of: window), files: files, index: index, thumbnail: thumbnail,
                                    source: source, address: address, origin: origin) { [weak self] in
            self?.overlay = nil
            onClose?()
        }
        overlay = o
        o.open()
        CraLog.note("media preview opens \(files[index].name) (\(o.kindName), \(source.rawValue))")
    }

    /// A download picked in the tray or on Library ▸ Downloads: previewed, with the list's other
    /// files the preview shows to step through. False when it isn't one it shows (it opens in its app).
    @discardableResult
    func showDownload(_ path: String, in list: [DownloadHistory.Listed], from thumbnail: NSRect?, over window: NSWindow,
                      origin: ((String) -> NSRect?)? = nil, onClose: (() -> Void)? = nil) -> Bool {
        let entries = list.compactMap { row -> DownloadHistory.Entry? in if case .finished(let e) = row { return e } else { return nil } }
        guard let b = MediaPreview.browse(entries.map(\.path), picked: path) else { return false }
        var dates: [String: Date] = [:]
        for e in entries where dates[e.path] == nil { dates[e.path] = e.date }
        let files = b.paths.map { MediaLibrary.File(path: $0, date: dates[$0] ?? Date()) }
        show(files, at: b.index, from: thumbnail, over: window, source: .downloads, origin: origin, onClose: onClose)
        return true
    }

    func close() { overlay?.close(animated: true) }

    static func browserWindow(of window: NSWindow) -> NSWindow {
        var w = window
        while let p = w.parent { w = p }
        return w
    }

    // MARK: cra://debug

    func debugState(_ label: String) {
        guard let overlay else { CraLog.note("media preview \(label): closed"); return }
        overlay.debugState(label)
    }

    func debugKey(_ name: String) {
        let codes: [String: UInt16] = ["escape": 53, "left": 123, "right": 124, "space": 49]
        guard let overlay, let code = codes[name] else { return }
        overlay.debugKey(code)
    }

    func debugBackdropClick() { overlay?.debugBackdropClick() }

    func debugToggleZoom() { overlay?.debugToggleZoom() }
}

private final class MediaPreviewOverlay: NSWindow {
    private weak var hostWindow: NSWindow?
    private var files: [MediaLibrary.File]
    private var index: Int
    private let thumbnail: NSRect?
    private let openedAt: Int
    private let source: MediaPreviewController.Source
    /// A web image's address (Copy Image Address).
    private let address: String?
    private let origin: ((String) -> NSRect?)?
    private let onClose: () -> Void
    private let root = OverlayRoot()
    private let panel = MediaPreviewPanel()
    private var closing = false
    /// The preview's keys, whichever window AppKit keeps key (a child panel isn't always made key).
    private var keys: Any?

    init(parent: NSWindow, files: [MediaLibrary.File], index: Int, thumbnail: NSRect?, source: MediaPreviewController.Source,
         address: String?, origin: ((String) -> NSRect?)?, onClose: @escaping () -> Void) {
        self.address = address
        hostWindow = parent
        self.files = files
        self.index = index
        self.thumbnail = thumbnail
        self.source = source
        self.origin = origin
        openedAt = index
        self.onClose = onClose
        super.init(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        root.onClickOutside = { [weak self] in self?.close(animated: true) }
        contentView = root
        root.addSubview(panel)
        panel.onClose = { [weak self] in self?.close(animated: true) }
        panel.onStep = { [weak self] in self?.step($0) }
        panel.onOpenInApp = { [weak self] in self?.openInApp() }
        panel.onMenu = { [weak self] in self?.fileMenu(at: $0) }
        panel.onFailed = { [weak self] in
            guard let self else { return }
            CraLog.note("media preview: \(self.files[self.index].name) shows in Quick Look instead")
        }
        layoutPanel()
        panel.show(files[index], canBack: index > 0, canForward: index < files.count - 1)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var kindName: String { panel.kind.rawValue }

    private func layoutPanel() {
        let bounds = NSRect(origin: .zero, size: frame.size)
        root.frame = bounds
        panel.frame = MediaPreview.panel(in: bounds)
        root.panelFrame = panel.frame
    }

    func open() {
        guard let parent = hostWindow else { return }
        parent.addChildWindow(self, ordered: .above)
        makeKeyAndOrderFront(nil)
        panel.focusContent()
        // Laid out and drawn once before measuring: the grow is computed from where the panel's
        // layer really is and where it is anchored.
        root.layoutSubtreeIfNeeded()
        root.displayIfNeeded()
        root.layer?.speed = MediaPreviewController.debugSpeed
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !self.closing, e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
            return self.handle(e.keyCode) ? nil : e
        }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let c = MediaPreview.curve
        let timing = CAMediaTimingFunction(controlPoints: c.0, c.1, c.2, c.3)
        let dim = CABasicAnimation(keyPath: "backgroundColor")
        dim.fromValue = NSColor.black.withAlphaComponent(0).cgColor
        dim.toValue = root.layer?.backgroundColor
        dim.duration = MediaPreview.openDuration
        dim.timingFunction = timing
        root.layer?.add(dim, forKey: "dim")
        guard let layer = panel.layer else { return }
        let from = reduce ? nil : startTransform()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from == nil ? 0 : 0.6
        fade.toValue = 1
        var animations: [CAAnimation] = [fade]
        let grow = CABasicAnimation(keyPath: "transform")
        // From the picked thumbnail, or (none to grow from) a touch smaller in place.
        grow.fromValue = NSValue(caTransform3D: from ?? (reduce ? CATransform3DIdentity : inPlace(0.96)))
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animations.append(grow)
        CraLog.note("media preview grows from \(from == nil ? "place" : "its item") (\(files[index].name))")
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = MediaPreview.openDuration
        group.timingFunction = timing
        layer.add(group, forKey: "open")
    }

    /// Where the panel's layer is anchored, in the overlay's coordinates: Core Animation scales
    /// about it. It is left where AppKit keeps it (moving it didn't hold).
    private var anchorInRoot: CGPoint {
        let a = panel.layer?.anchorPoint ?? .zero
        return CGPoint(x: panel.frame.minX + a.x * panel.frame.width, y: panel.frame.minY + a.y * panel.frame.height)
    }

    /// The panel scaled by `s` about its own centre.
    private func inPlace(_ s: CGFloat) -> CATransform3D {
        let t = MediaPreview.shift(keeping: CGPoint(x: panel.frame.midX, y: panel.frame.midY), about: anchorInRoot, scale: s)
        return CATransform3DScale(CATransform3DMakeTranslation(t.x, t.y, 0), s, s, 1)
    }

    /// Where the file shown now sits in the list it came from (screen points): asked of the list,
    /// so it is right after a scroll or a step; else the picked thumbnail while that file shows.
    private func originRect() -> NSRect? {
        if let origin, let r = origin(files[index].path), r.width > 0, r.height > 0 { return r }
        return index == openedAt ? thumbnail : nil
    }

    /// The panel scaled and moved so its picture lies inside the item's thumbnail (it grows out of
    /// it and shrinks back into it; CraCore MediaPreview.origin).
    private func startTransform() -> CATransform3D? {
        guard let thumb = originRect(), panel.layer != nil else { return nil }
        let local = NSRect(origin: NSPoint(x: thumb.minX - frame.minX, y: thumb.minY - frame.minY), size: thumb.size)
        guard let o = MediaPreview.origin(media: panel.mediaFrameInRoot(), about: anchorInRoot, origin: local) else { return nil }
        var t = CATransform3DMakeTranslation(o.shift.x, o.shift.y, 0)
        t = CATransform3DScale(t, o.scale, o.scale, 1)
        return t
    }

    func close(animated: Bool) {
        guard !closing else { return }
        closing = true
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        onClose()
        CraLog.note("media preview closes")
        let finish = { [weak self] in
            guard let self else { return }
            self.hostWindow?.removeChildWindow(self)
            self.orderOut(nil)
            self.panel.stop()
            self.hostWindow?.makeKey()
        }
        guard animated, let layer = panel.layer else { finish(); return }
        let c = MediaPreview.curve
        CATransaction.begin()
        CATransaction.setCompletionBlock(finish)
        panel.resetZoom()
        let back = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : startTransform()
        CraLog.note("media preview closes into \(back == nil ? "place" : "its item") (\(files[index].name))")
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.toValue = NSValue(caTransform3D: back ?? inPlace(0.96))
        // Into the item it stays visible most of the way, then fades as it lands (no small panel left
        // over the thumbnail to blink out); in place it fades as it shrinks.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = back == nil ? [1, 0] : [1, 0.9, 0]
        fade.keyTimes = back == nil ? [0, 1] : [0, 0.6, 1]
        let group = CAAnimationGroup()
        group.animations = [shrink, fade]
        group.duration = MediaPreview.closeDuration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, c.2, c.3)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "close")
        let undim = CABasicAnimation(keyPath: "backgroundColor")
        undim.toValue = NSColor.black.withAlphaComponent(0).cgColor
        undim.duration = MediaPreview.closeDuration
        undim.fillMode = .forwards
        undim.isRemovedOnCompletion = false
        root.layer?.add(undim, forKey: "undim")
        CATransaction.commit()
    }

    private func step(_ delta: Int) {
        guard let next = MediaPreview.step(index, by: delta, count: files.count) else { NSSound.beep(); return }
        index = next
        panel.show(files[index], canBack: index > 0, canForward: index < files.count - 1)
        panel.focusContent()
        CraLog.note("media preview shows \(files[index].name) (\(panel.kind.rawValue))")
    }

    private func openInApp() {
        let url = URL(fileURLWithPath: files[index].path)
        NSWorkspace.shared.open(url)
        close(animated: true)
    }

    /// The ⋯ menu: Arc's media menu (the tile's right-click, CraCore MediaLibrary.Action), or a
    /// download's (its row's menu in the tray and on Library ▸ Downloads).
    private func fileMenu(at point: NSPoint) {
        let file = files[index]
        let menu: NSMenu
        switch source {
        case .media:
            guard let store = (NSApp.delegate as? AppDelegate)?.store else { return }
            menu = MediaMenu.make(for: file, store: store) { [weak self] action in
                guard action == .hide else { return }
                self?.drop(file)
                NotificationCenter.default.post(name: MediaPreviewController.hidden, object: nil)
            }
        case .downloads:
            guard let entry = DownloadHistory.shared.entries.last(where: { $0.path == file.path }) else { return }
            menu = NSMenu()
            menu.autoenablesItems = false
            DownloadRowMenu.fill(menu, for: .finished(entry)) { [weak self] action in
                if action == .hide || action == .moveToTrash { self?.drop(file) }
            }
        case .webImage:
            menu = webImageMenu(file)
        }
        menu.popUp(positioning: nil, at: point, in: panel)
    }

    /// A web image's ⋯: Copy Image, Copy Image Address, Save to Downloads.
    private func webImageMenu(_ file: MediaLibrary.File) -> NSMenu {
        let url = URL(fileURLWithPath: file.path)
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Copy Image") {
            NSPasteboard.general.clearContents()
            var objects: [NSPasteboardWriting] = [url as NSURL]
            if let image = NSImage(contentsOf: url) { objects.insert(image, at: 0) }
            NSPasteboard.general.writeObjects(objects)
        }
        if let address, !address.lowercased().hasPrefix("data:") {
            MenuItems.add(m, "Copy Image Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
            }
        }
        m.addItem(.separator())
        MenuItems.add(m, "Save to Downloads") {
            let folder = DownloadDestinations.folder(profileID: nil)
            let dest = DownloadFileName.unique(file.name, in: folder) { FileManager.default.fileExists(atPath: $0) }
            guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil else { return }
            DownloadHistory.shared.add(path: dest.path, profile: nil)
            CraLog.note("image preview: saved to Downloads")
        }
        return m
    }

    /// A file hidden or trashed from ⋯: the next one shows, or the preview closes with nothing left.
    private func drop(_ file: MediaLibrary.File) {
        guard let i = files.firstIndex(of: file) else { return }
        files.remove(at: i)
        if files.isEmpty { close(animated: true); return }
        index = min(i, files.count - 1)
        panel.show(files[index], canBack: index > 0, canForward: index < files.count - 1)
    }

    /// Esc closes, ← → step, Space plays or pauses a video and closes anything else (as Quick
    /// Look); a WebM's web view keeps Space for its own player.
    private func handle(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: close(animated: true)
        case 123: step(-1)
        case 124: step(1)
        case 49:
            switch panel.kind {
            case .video: panel.togglePlayback()
            case .webVideo: return false
            case .image, .document: close(animated: true)
            }
        default: return false
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event.keyCode) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) { close(animated: true) }

    func debugKey(_ code: UInt16) { _ = handle(code) }

    func debugToggleZoom() { panel.debugToggleZoom() }

    /// A click on the dimmed window 6 pt in from its corner, through the root's own hit test.
    func debugBackdropClick() {
        guard let e = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 6, y: 6), modifierFlags: [], timestamp: 0,
                                         windowNumber: windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        root.mouseDown(with: e)
    }

    func debugState(_ label: String) {
        let f = files[index]
        CraLog.note("media preview \(label): shown name=\(f.name) kind=\(panel.kind.rawValue) index=\(index + 1)/\(files.count) "
            + "source=\(source.rawValue) open=\"\(panel.openTitle)\" back=\(index > 0 ? 1 : 0) forward=\(index < files.count - 1 ? 1 : 0) "
            + "panel=\(Int(panel.frame.width))x\(Int(panel.frame.height)) in \(Int(frame.width))x\(Int(frame.height)) playing=\(panel.isPlaying ? 1 : 0) zoom=\(panel.zoomState)")
    }
}

/// The dimmed window: a click outside the panel closes it.
private final class OverlayRoot: NSView {
    var panelFrame: NSRect = .zero
    var onClickOutside: () -> Void = {}
    override func mouseDown(with event: NSEvent) {
        if !panelFrame.contains(convert(event.locationInWindow, from: nil)) { onClickOutside() }
    }
}

/// The panel: a blurred copy of the file's picture behind everything, a light frosted header with
/// dark ink (Arc's, whatever the picture: 11 Nov 2026 stills), and the file under it.
private final class MediaPreviewPanel: NSView {
    var onClose: () -> Void = {}
    var onStep: (Int) -> Void = { _ in }
    var onOpenInApp: () -> Void = {}
    var onMenu: (NSPoint) -> Void = { _ in }
    /// A video AVFoundation can't play, or a picture AppKit can't draw, went to Quick Look.
    var onFailed: () -> Void = {}
    private(set) var kind: MediaPreview.Kind = .image

    private let backdrop = CALayer()
    private let wash = CALayer()
    private let header = NSView()
    private let closeButton = HeaderButton(symbol: "xmark", label: "Close")
    private let backButton = HeaderButton(symbol: "chevron.left", label: "Previous")
    private let forwardButton = HeaderButton(symbol: "chevron.right", label: "Next")
    private let name = NSTextField(labelWithString: "")
    private let age = NSTextField(labelWithString: "")
    private let moreButton = HeaderButton(symbol: "ellipsis", label: "More")
    private let openButton = HeaderButton(symbol: "arrow.up.right", label: "Open in Preview", title: "Open in Preview", filled: true)
    private let picture = PreviewImageScroll()
    private var video: PreviewVideoView?
    private var web: WKWebView?
    private var document: QLPreviewView?
    /// Rounds a document's or a web video's corners like the picture's.
    private let clip = NSView()
    private var mediaSize = NSSize(width: 4, height: 3)
    private var shownURL: URL?

    var openTitle: String { openButton.title }
    var isPlaying: Bool { video?.isPlaying ?? false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = MediaPreview.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.82, alpha: 1).cgColor
        backdrop.contentsGravity = .resizeAspectFill
        layer?.addSublayer(backdrop)
        // Arc's body is the blurred picture nearly as it is; its header a light frosted band.
        wash.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        layer?.addSublayer(wash)
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        addSubview(header)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.textColor = NSColor.black.withAlphaComponent(0.85)
        name.lineBreakMode = .byTruncatingMiddle
        age.font = .systemFont(ofSize: 13)
        age.textColor = NSColor.black.withAlphaComponent(0.4)
        for v in [closeButton, backButton, forwardButton, name, age, moreButton, openButton] as [NSView] { header.addSubview(v) }
        closeButton.action = { [weak self] _ in self?.onClose() }
        backButton.action = { [weak self] _ in self?.onStep(-1) }
        forwardButton.action = { [weak self] _ in self?.onStep(1) }
        openButton.action = { [weak self] _ in self?.onOpenInApp() }
        moreButton.action = { [weak self] b in
            guard let self else { return }
            self.onMenu(self.convert(NSPoint(x: b.frame.minX, y: b.frame.minY - 4), from: b.superview))
        }
        addSubview(picture)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 6
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.isHidden = true
        addSubview(clip)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A click on the panel's own background does nothing (the dimmed window around it closes).
    override func mouseDown(with event: NSEvent) {}

    func show(_ file: MediaLibrary.File, canBack: Bool, canForward: Bool) {
        name.stringValue = file.name
        age.stringValue = MediaPreview.age(file.date, now: Date())
        backButton.isEnabled = canBack
        forwardButton.isEnabled = canForward
        let url = URL(fileURLWithPath: file.path)
        let app = NSWorkspace.shared.urlForApplication(toOpen: url).map { FileManager.default.displayName(atPath: $0.path) }
        openButton.setTitle(MediaPreview.openTitle(appName: app))
        stop()
        shownURL = url
        picture.isHidden = true
        picture.image = nil
        clip.isHidden = true
        backdrop.contents = nil
        kind = MediaPreview.kind(of: file.path) ?? .document
        switch kind {
        case .image:
            if let image = NSImage(contentsOf: url), image.isValid, image.size.width > 0 {
                picture.isHidden = false
                picture.image = image
                if let rep = image.representations.first, rep.pixelsWide > 0 {
                    mediaSize = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
                } else {
                    mediaSize = image.size
                }
                setBackdrop(image)
            } else {
                showDocument(url)
                onFailed()
            }
        case .video:
            showVideo(url)
        case .webVideo:
            showWebVideo(url)
        case .document:
            showDocument(url)
        }
        if kind != .image {
            MediaScanner.shared.thumbnail(file, size: 400) { [weak self] img in
                guard self?.shownURL == url else { return }
                self?.setBackdrop(img)
            }.map(setBackdrop)
        }
        needsLayout = true
    }

    private func showVideo(_ url: URL) {
        let v = PreviewVideoView(url: url)
        v.onFailed = { [weak self, weak v] in
            // WebM and the like: Quick Look shows what it can.
            guard let self, let v, self.video === v else { return }
            self.stop()
            self.showDocument(url)
            self.onFailed()
            self.needsLayout = true
        }
        addSubview(v)
        video = v
        mediaSize = NSSize(width: 16, height: 9)
        let asset = AVURLAsset(url: url)
        Task { @MainActor [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize), let t = try? await track.load(.preferredTransform) else { return }
            let r = CGRect(origin: .zero, size: size).applying(t)
            guard self?.shownURL == url else { return }
            self?.mediaSize = NSSize(width: abs(r.width), height: abs(r.height))
            self?.needsLayout = true
        }
        v.play()
    }

    private func showWebVideo(_ url: URL) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let w = WKWebView(frame: .zero, configuration: config)
        w.loadFileURL(url, allowingReadAccessTo: url)
        clip.addSubview(w)
        clip.isHidden = false
        web = w
        kind = .webVideo
    }

    private func showDocument(_ url: URL) {
        kind = .document
        clip.isHidden = false
        guard let q = QLPreviewView(frame: .zero, style: .normal) else { return }
        q.shouldCloseWithWindow = false
        q.autostarts = true
        q.previewItem = url as NSURL
        clip.addSubview(q)
        document = q
    }

    /// Up and down scroll a document, Space or a click plays a web video.
    func focusContent() {
        if let v = document ?? web { window?.makeFirstResponder(v) }
    }

    func togglePlayback() { video?.toggle() }

    /// A zoomed picture goes back to fitting the panel (before it shrinks into its item).
    func resetZoom() { if kind == .image { picture.fit() } }

    var zoomState: String { kind == .image ? picture.state : "-" }

    /// A double-click in the middle of the picture.
    func debugToggleZoom() {
        guard kind == .image, let doc = picture.documentView else { return }
        picture.toggleZoom(at: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
    }

    func stop() {
        video?.stop()
        video?.removeFromSuperview()
        video = nil
        web?.pauseAllMediaPlayback()
        web?.removeFromSuperview()
        web = nil
        document?.close()
        document?.removeFromSuperview()
        document = nil
    }

    /// The panel's backdrop: the picture itself (a document's or video's Quick Look picture), blurred.
    private func setBackdrop(_ image: NSImage?) {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { backdrop.contents = nil; return }
        let ci = CIImage(cgImage: cg)
        let small = ci.transformed(by: CGAffineTransform(scaleX: 256 / max(ci.extent.width, 1), y: 256 / max(ci.extent.width, 1)))
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: 24).cropped(to: small.extent)
        let ctx = CIContext()
        backdrop.contents = ctx.createCGImage(blurred, from: small.extent)
    }

    /// Where the file is drawn (a picture or video fitted, a document or web video filling the body).
    private var mediaRect: NSRect {
        let bounds = NSRect(origin: .zero, size: self.bounds.size)
        switch kind {
        case .image, .video: return MediaPreview.media(mediaSize, in: bounds)
        case .webVideo, .document: return MediaPreview.body(in: bounds)
        }
    }

    /// The picture's frame in the overlay's coordinates.
    func mediaFrameInRoot() -> NSRect { mediaRect.offsetBy(dx: frame.minX, dy: frame.minY) }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        wash.frame = bounds
        CATransaction.commit()
        let h = MediaPreview.headerHeight
        header.frame = NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        // Arc: ✕ 24 pt in, ‹ at 60, › at 92 (centres); the name 112 pt in; ⋯ and the button 7 pt from the right.
        closeButton.frame = NSRect(x: 24 - 15, y: 8, width: 30, height: 30)
        backButton.frame = NSRect(x: 60 - 14, y: 8, width: 28, height: 30)
        forwardButton.frame = NSRect(x: 92 - 14, y: 8, width: 28, height: 30)
        let ow = openButton.fittingWidth
        openButton.frame = NSRect(x: bounds.width - 7 - ow, y: 8, width: ow, height: 30)
        moreButton.frame = NSRect(x: openButton.frame.minX - 4 - 32, y: 8, width: 32, height: 30)
        let ageW = ceil(age.intrinsicContentSize.width)
        let nameW = min(ceil(name.attributedStringValue.size().width) + 8, max(0, moreButton.frame.minX - 16 - 112 - 8 - ageW))
        name.frame = NSRect(x: 112, y: (h - 17) / 2, width: nameW, height: 17)
        age.frame = NSRect(x: name.frame.maxX + 8, y: (h - 17) / 2, width: ageW, height: 17)
        let m = mediaRect
        // The picture's scroll view spans the body, so a zoomed picture can fill it; at rest it
        // draws the picture fitted and centred, where `mediaRect` says.
        picture.frame = MediaPreview.body(in: NSRect(origin: .zero, size: bounds.size))
        video?.frame = m
        clip.frame = m
        for v in clip.subviews { v.frame = clip.bounds }
    }
}

/// A video in the panel: AVFoundation's picture under Arc's round button (a frosted disc with a
/// white ⏸/▶ and the time played as a white ring round its edge, from the top, clockwise). The
/// button shows while the pointer moves over the video or it is paused; a click anywhere on the
/// video, the button or Space plays and pauses.
private final class PreviewVideoView: NSView {
    var onFailed: () -> Void = {}
    private let player: AVPlayer
    private let playerLayer = AVPlayerLayer()
    private let control = PreviewPlayButton()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var idle: Timer?
    private var ended = false

    var isPlaying: Bool { player.rate > 0 }

    init(url: URL) {
        player = AVPlayer(url: url)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        addSubview(control)
        control.onPress = { [weak self] in self?.toggle() }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshProgress() }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnd() }
        }
        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onFailed() } }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func play() {
        if ended { player.seek(to: .zero); ended = false }
        player.play()
        control.playing = true
        showControl()
    }

    func toggle() {
        if isPlaying {
            player.pause()
            control.playing = false
            showControl()
        } else {
            play()
        }
        CraLog.note("media preview video \(isPlaying ? "plays" : "pauses")")
    }

    func stop() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        statusObservation = nil
        idle?.invalidate()
    }

    private func didEnd() {
        ended = true
        control.playing = false
        control.progress = 1
        showControl()
    }

    private func refreshProgress() {
        guard let item = player.currentItem else { return }
        let d = item.duration.seconds
        guard d.isFinite, d > 0 else { return }
        control.progress = min(1, max(0, player.currentTime().seconds / d))
    }

    /// The button comes back, and goes again 1.5 s after the pointer stops while the video plays.
    private func showControl() {
        idle?.invalidate()
        control.animator().alphaValue = 1
        guard isPlaying else { return }
        idle = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                NSAnimationContext.runAnimationGroup { $0.duration = 0.25; self.control.animator().alphaValue = 0 }
            }
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        let s = PreviewPlayButton.side
        control.frame = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { showControl() }
    override func mouseEntered(with event: NSEvent) { showControl() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        toggle()
    }
}

/// Arc's round play/pause button over a preview's video.
private final class PreviewPlayButton: NSView {
    static let side: CGFloat = 46
    var onPress: () -> Void = {}
    var playing = false { didSet { if playing != oldValue { refreshGlyph() } } }
    var progress: Double = 0 {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            ring.strokeEnd = CGFloat(progress)
            CATransaction.commit()
        }
    }
    private let disc = CALayer()
    private let ring = CAShapeLayer()
    private let glyph = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        disc.backgroundColor = NSColor(white: 0.62, alpha: 0.5).cgColor
        disc.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        disc.borderWidth = 1
        layer?.addSublayer(disc)
        ring.fillColor = nil
        ring.strokeColor = NSColor.white.cgColor
        ring.lineWidth = 2.5
        ring.lineCap = .round
        ring.strokeEnd = 0
        layer?.addSublayer(ring)
        glyph.imageScaling = .scaleNone
        glyph.contentTintColor = .white
        addSubview(glyph)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refreshGlyph()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refreshGlyph() {
        let symbol = playing ? "pause.fill" : "play.fill"
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: playing ? "Pause" : "Play")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .bold))
        setAccessibilityLabel(playing ? "Pause" : "Play")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.frame = bounds
        disc.cornerRadius = bounds.width / 2
        ring.frame = bounds
        // From the top, clockwise (the layer is y-up), 4 pt inside the disc's edge.
        let r = bounds.width / 2 - 4
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: r, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        ring.path = path
        CATransaction.commit()
        let s = glyph.image?.size ?? .zero
        // ▶ sits a touch right of centre, as it reads centred.
        let nudge: CGFloat = playing ? 0 : 1.5
        glyph.frame = NSRect(x: (bounds.width - s.width) / 2 + nudge, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress()
    }
}

/// A header control: a glyph (✕ ‹ › ⋯) or a filled button with a title and a trailing glyph, in
/// Arc's dark ink on the light header.
private final class HeaderButton: NSView {
    var action: (HeaderButton) -> Void = { _ in }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.35 } }
    private let glyph = NSImageView()
    private let text = NSTextField(labelWithString: "")
    private let filled: Bool
    private var hovering = false { didSet { refresh() } }
    private static let ink = NSColor.black.withAlphaComponent(0.8)

    var title: String { text.stringValue }

    init(symbol: String, label: String, title: String? = nil, filled: Bool = false) {
        self.filled = filled
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: title == nil ? 14 : 12, weight: .semibold))
        glyph.contentTintColor = Self.ink
        addSubview(glyph)
        if let title { setTitle(title) }
        text.font = .systemFont(ofSize: 13, weight: .semibold)
        text.textColor = Self.ink
        addSubview(text)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title ?? label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ t: String) {
        text.stringValue = t
        setAccessibilityLabel(t)
        needsLayout = true
        superview?.superview?.needsLayout = true
    }

    /// The title's own width (the label's intrinsic size came out short for "Open in Microsoft Excel").
    private var textWidth: CGFloat { ceil(text.attributedStringValue.size().width) + 4 }

    var fittingWidth: CGFloat { text.stringValue.isEmpty ? 32 : textWidth + 12 + 6 + 12 + 10 }

    private func refresh() {
        let base: CGFloat = filled ? 0.06 : 0
        layer?.backgroundColor = NSColor.black.withAlphaComponent(base + (hovering && isEnabled ? 0.06 : 0)).cgColor
    }

    override func layout() {
        super.layout()
        let s = glyph.image?.size ?? .zero
        if text.stringValue.isEmpty {
            glyph.frame = NSRect(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
        } else {
            let tw = textWidth
            text.frame = NSRect(x: 12, y: (bounds.height - 17) / 2, width: tw, height: 17)
            glyph.frame = NSRect(x: text.frame.maxX + 6, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action(self)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A picture in the panel that zooms (11 Nov 2026): a pinch on the trackpad, or a double-click
/// between fitting the panel and 100 % (its own size) at the clicked point; zoomed in, a drag pans
/// it. Smaller than the view, it stays centred.
private final class PreviewImageScroll: NSScrollView {
    private let document = PreviewImageDocument()
    private var naturalSize = NSSize(width: 1, height: 1)
    /// Fitted, it follows the panel's size; zoomed, it keeps the zoom.
    private var atFit = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false
        let clip = CenteringClipView()
        clip.drawsBackground = false
        contentView = clip
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        documentView = document
        document.onDoubleClick = { [weak self] p in self?.toggleZoom(at: p) }
        document.zoomed = { [weak self] in self?.isZoomed ?? false }
        NotificationCenter.default.addObserver(self, selector: #selector(liveMagnifyEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    var image: NSImage? {
        get { document.image }
        set {
            document.image = newValue
            let size = newValue?.size ?? .zero
            naturalSize = size.width > 0 && size.height > 0 ? size : NSSize(width: 1, height: 1)
            document.frame = NSRect(origin: .zero, size: naturalSize)
            fit()
        }
    }

    private var fitMagnification: CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / naturalSize.width, bounds.height / naturalSize.height)
    }

    var isZoomed: Bool { magnification > fitMagnification * 1.01 }

    /// "fit", "100%" or the zoom as a percentage, for cra://debug.
    var state: String {
        if abs(magnification - fitMagnification) < 0.005 { return "fit" }
        return "\(Int((magnification * 100).rounded()))%"
    }

    func fit() {
        let f = fitMagnification
        minMagnification = min(f, 1)
        maxMagnification = max(f * 8, 8)
        magnification = f
        atFit = true
        refreshCorners()
    }

    override var magnification: CGFloat { didSet { refreshCorners() } }

    /// The picture's 4 pt corners stay 4 pt on screen whatever the zoom.
    private func refreshCorners() {
        document.wantsLayer = true
        document.layer?.cornerRadius = 4 / max(magnification, 0.01)
        document.layer?.masksToBounds = true
        window?.invalidateCursorRects(for: document)
    }

    /// Fitted → 100 % at the clicked point; anything else → fitted.
    func toggleZoom(at point: NSPoint) {
        let f = fitMagnification
        let target: CGFloat = atFit && abs(f - 1) > 0.01 ? 1 : f
        atFit = abs(target - f) < 0.001
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setMagnification(target, centeredAt: point)
        } completionHandler: { [weak self] in self?.refreshCorners() }
        CraLog.note("media preview zooms to \(atFit ? "fit" : "100%")")
    }

    @objc private func liveMagnifyEnded() {
        atFit = abs(magnification - fitMagnification) < 0.01
        refreshCorners()
    }

    override func layout() {
        super.layout()
        if atFit { fit() }
    }

    /// A trackpad scroll pans a zoomed picture; at fit it has nowhere to go.
    override func scrollWheel(with event: NSEvent) {
        if isZoomed { super.scrollWheel(with: event) }
    }
}

/// Keeps a document smaller than the view in its middle.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let d = documentView?.frame else { return r }
        if r.width > d.width { r.origin.x = (d.width - r.width) / 2 }
        if r.height > d.height { r.origin.y = (d.height - r.height) / 2 }
        return r
    }
}

/// The picture itself: a double-click zooms, a drag pans while zoomed (an open hand over it).
private final class PreviewImageDocument: NSImageView {
    var onDoubleClick: (NSPoint) -> Void = { _ in }
    var zoomed: () -> Bool = { false }
    private var dragFrom: NSPoint?
    private var originFrom: NSPoint = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageScaling = .scaleAxesIndependently
        animates = true
        isEditable = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick(convert(event.locationInWindow, from: nil)); return }
        guard zoomed(), let clip = enclosingScrollView?.contentView else { return }
        dragFrom = event.locationInWindow
        originFrom = clip.bounds.origin
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragFrom, let scroll = enclosingScrollView else { return }
        let m = max(scroll.magnification, 0.01)
        let p = event.locationInWindow
        let to = NSPoint(x: originFrom.x - (p.x - start.x) / m, y: originFrom.y - (p.y - start.y) / m)
        scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(NSRect(origin: to, size: scroll.contentView.bounds.size)).origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    override func mouseUp(with event: NSEvent) {
        if dragFrom != nil { NSCursor.pop() }
        dragFrom = nil
    }

    override func resetCursorRects() {
        if zoomed() { addCursorRect(visibleRect, cursor: .openHand) }
    }

    override var mouseDownCanMoveWindow: Bool { false }
}
