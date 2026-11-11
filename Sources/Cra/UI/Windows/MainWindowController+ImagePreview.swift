import AppKit
import CraCEF

/// A web page's image in Cra's preview card (CraCore WebImagePreview, 11 Nov 2026): its context
/// menu's "Open Image in Preview", or a Shift-click on an image that isn't a link. The preview grows
/// out of the image where it sits on the page, and zooms and pans like any picture in it.
extension MainWindowController {
    func browserManagerPreviewImage(_ url: String?, at point: NSPoint, tabID: UUID) {
        guard let rt = browsers.runtime(for: tabID) else { return }
        previewImage(in: rt, at: point, url: url, fromShiftClick: false)
    }

    func installImageClickMonitor() {
        imageClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] e in
            guard let self else { return e }
            let shiftOnly = e.modifierFlags.intersection([.command, .shift, .option, .control]) == .shift
            if e.type == .leftMouseDown {
                self.shiftPress = shiftOnly && e.clickCount == 1 ? (e.window, e.locationInWindow, e.timestamp) : nil
                return e
            }
            // A click, not a drag (Shift-dragging extends a selection) or a slow press.
            guard shiftOnly, let press = self.shiftPress, press.window === e.window,
                  hypot(e.locationInWindow.x - press.at.x, e.locationInWindow.y - press.at.y) < 4,
                  e.timestamp - press.time < 0.8, let hit = self.pagePoint(of: e) else { return e }
            self.shiftPress = nil
            self.previewImage(in: hit.runtime, at: hit.point, url: nil, fromShiftClick: true)
            return e
        }
    }

    /// The visible page under `event` and where in it (page points from its top left).
    private func pagePoint(of event: NSEvent) -> (runtime: TabRuntime, point: NSPoint)? {
        for id in browsers.visibleTabIDs {
            guard let rt = browsers.runtime(for: id) else { continue }
            let view = rt.hostWindow.flatMap { EmbeddedPages.pageViews(of: $0)?.last } ?? rt.browser.containerView
            guard view.window === event.window, !view.isHiddenOrHasHiddenAncestor else { continue }
            let p = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(p) else { continue }
            return (rt, NSPoint(x: p.x, y: view.isFlipped ? p.y : view.bounds.height - p.y))
        }
        return nil
    }

    /// The image at `point` (page points from the top left): found in the page, fetched, and shown.
    func previewImage(in rt: TabRuntime, at point: NSPoint, url: String?, fromShiftClick: Bool) {
        let b = rt.browser
        let scale = window?.backingScaleFactor ?? 2
        let script = WebImagePreview.imageScript(x: point.x * scale, y: point.y * scale)
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        b.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self, weak b] result, _ in
            MainActor.assumeIsolated {
                guard let self, let b else { return }
                let value = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                    .flatMap { ($0["result"] as? [String: Any])?["value"] as? [String: Any] }
                if fromShiftClick {
                    let link = value?["link"] as? Bool ?? false
                    guard WebImagePreview.shiftClickPreviews(shiftOnly: true, isImage: value != nil, insideLink: link) else {
                        if link { CraLog.note("image preview: a Shift-click on a linked image stays the link's") }
                        return
                    }
                }
                guard let src = url ?? value?["src"] as? String, !src.isEmpty else { return }
                // Where the image is: on screen for the grow, in device pixels for a crop.
                var origin: NSRect?
                var device: CGRect?
                if let value, let page = self.pageScreenRect(rt),
                   let r = ContentCapture.elementRect(fromPicker: value, scale: scale, pageBounds: CGRect(origin: .zero, size: page.size)) {
                    origin = NSRect(x: page.minX + r.minX, y: page.maxY - r.maxY, width: r.width, height: r.height)
                    device = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
                }
                CraLog.note("image preview: \(fromShiftClick ? "a Shift-click" : "the menu") on an image from a \(URL(string: src)?.scheme ?? "?"): address")
                self.loadWebImage(src, browser: b, crop: device) { [weak self] data, mime in
                    guard let self, let data, let window = self.window else {
                        if data == nil { self?.showToast("Couldn’t Open the Image") }
                        return
                    }
                    guard let file = Self.writePreviewImage(data, name: WebImagePreview.fileName(url: src, mimeType: mime)) else { return }
                    MediaPreviewController.shared.show([MediaLibrary.File(path: file.path, date: Date())], at: 0, from: origin, over: window,
                                                       source: .webImage, address: src)
                }
            }
        }
    }

    /// The image's bytes: a data: address decoded, an http(s) one fetched (the page's cache isn't
    /// Cra's to read); failing that, the image as the page shows it, cut from a capture of the page.
    private func loadWebImage(_ src: String, browser b: CraBrowser, crop: CGRect?, done: @escaping @MainActor (Data?, String?) -> Void) {
        if let d = WebImagePreview.decodeDataURL(src), NSImage(data: d.data) != nil { done(d.data, d.mimeType); return }
        let fallback: @MainActor () -> Void = { [weak b] in
            guard let b, let crop else { done(nil, nil); return }
            b.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","captureBeyondViewport":false}"#) { shot, _ in
                MainActor.assumeIsolated {
                    guard let image = Self.screenshotImage(shot), let part = image.cropping(to: crop.integral),
                          let png = NSBitmapImageRep(cgImage: part).representation(using: .png, properties: [:]) else { done(nil, nil); return }
                    CraLog.note("image preview: taken from the page's picture")
                    done(png, "image/png")
                }
            }
        }
        guard let u = URL(string: src), ["http", "https"].contains(u.scheme?.lowercased() ?? "") else { fallback(); return }
        var request = URLRequest(url: u, timeoutInterval: 15)
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let mime = response?.mimeType
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if ok, let data, NSImage(data: data) != nil { done(data, mime) } else { fallback() }
                }
            }
        }.resume()
    }

    /// Kept in the temporary folder, each in a folder of its own so it keeps the image's own name;
    /// the last session's go the first time. Save to Downloads in the preview's ⋯ keeps one.
    private static func writePreviewImage(_ data: Data, name: String) -> URL? {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("Cra Image Preview", isDirectory: true)
        if !clearedPreviewImages {
            clearedPreviewImages = true
            try? fm.removeItem(at: base)
        }
        let dir = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = DownloadFileName.unique(name, in: dir) { fm.fileExists(atPath: $0) }
        do { try data.write(to: url) } catch { return nil }
        return url
    }

    private static var clearedPreviewImages = false

    // MARK: cra://debug

    /// imagePreview=x,y[&shift=1]: the menu's Open Image in Preview (or a Shift-click) at page point (x, y).
    func debugPreviewImage(at point: NSPoint, shiftClick: Bool) {
        guard let rt = browsers.visibleRuntime else { return }
        previewImage(in: rt, at: point, url: nil, fromShiftClick: shiftClick)
    }
}
