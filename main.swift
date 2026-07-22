import AppKit
import UniformTypeIdentifiers

// MARK: - Preferences (persisted in UserDefaults)
enum Quality: String, CaseIterable {
    case high, medium, low

    var label: String {
        switch self {
        case .high:   return "High"
        case .medium: return "Medium"
        case .low:    return "Low"
        }
    }

    var palettegen: String {
        switch self {
        case .high:   return "palettegen=stats_mode=diff"
        case .medium: return "palettegen=stats_mode=diff:max_colors=128"
        case .low:    return "palettegen=max_colors=64"
        }
    }

    var paletteuse: String {
        switch self {
        case .high:   return "paletteuse=dither=bayer:bayer_scale=3"
        case .medium: return "paletteuse=dither=bayer:bayer_scale=4"
        case .low:    return "paletteuse=dither=bayer:bayer_scale=5"
        }
    }
}

enum OutputMode: String {
    case nextToOriginal, askEachTime, customFolder
}

enum Prefs {
    static let fpsChoices = [10, 15, 20, 30]
    static let sizeChoices = [100, 75, 50, 33]

    private static let defaults = UserDefaults.standard

    static var fps: Int {
        get {
            let v = defaults.integer(forKey: "fps")
            return fpsChoices.contains(v) ? v : 15
        }
        set { defaults.set(newValue, forKey: "fps") }
    }

    static var sizePercent: Int {
        get {
            let v = defaults.integer(forKey: "sizePercent")
            return sizeChoices.contains(v) ? v : 100
        }
        set { defaults.set(newValue, forKey: "sizePercent") }
    }

    static var quality: Quality {
        get { Quality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .high }
        set { defaults.set(newValue.rawValue, forKey: "quality") }
    }

    static var outputMode: OutputMode {
        get { OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "") ?? .nextToOriginal }
        set { defaults.set(newValue.rawValue, forKey: "outputMode") }
    }

    static var customFolderPath: String {
        get { defaults.string(forKey: "customFolderPath") ?? "" }
        set { defaults.set(newValue, forKey: "customFolderPath") }
    }

    // Two-pass palette in one filter graph: good colors + crisp text, small-ish files.
    // [scale,]fps=N,split[s0][s1];[s0]<palettegen>[p];[s1][p]<paletteuse>
    static var filterComplex: String {
        var filters: [String] = []
        if sizePercent < 100 {
            // -2 keeps the height even (required by many encoders) and preserves aspect.
            filters.append("scale=iw*\(sizePercent)/100:-2:flags=lanczos")
        }
        filters.append("fps=\(fps)")
        let chain = filters.joined(separator: ",")
        return "\(chain),split[s0][s1];[s0]\(quality.palettegen)[p];[s1][p]\(quality.paletteuse)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var lastOutputs: [URL] = []
    private var isConverting = false
    private var ffmpegPath: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ffmpegPath = Self.locateFFmpeg()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "film.stack",
                                 accessibilityDescription: "Gifford") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "GIF"
            }
            button.imagePosition = .imageLeading
        }
        statusItem.menu = menu
        rebuildMenu()
    }

    // MARK: Menu
    private func rebuildMenu() {
        menu.removeAllItems()

        let convert = NSMenuItem(
            title: isConverting ? "Converting…" : "Convert Recording(s) to GIF…",
            action: (isConverting || ffmpegPath == nil) ? nil : #selector(convertAction),
            keyEquivalent: "")
        convert.target = self
        menu.addItem(convert)

        if ffmpegPath == nil {
            let warn = NSMenuItem(title: "⚠︎ ffmpeg not found — click to fix",
                                  action: #selector(ffmpegHelp), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        if !lastOutputs.isEmpty {
            menu.addItem(.separator())
            let title = lastOutputs.count == 1
                ? "Reveal GIF in Finder"
                : "Reveal \(lastOutputs.count) GIFs in Finder"
            let reveal = NSMenuItem(title: title, action: #selector(revealAction), keyEquivalent: "")
            reveal.target = self
            menu.addItem(reveal)
        }

        menu.addItem(.separator())
        menu.addItem(fpsMenuItem())
        menu.addItem(sizeMenuItem())
        menu.addItem(qualityMenuItem())
        menu.addItem(outputMenuItem())

        menu.addItem(.separator())
        let info = NSMenuItem(title: summaryLine(), action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(NSMenuItem(title: "Quit Gifford", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func fpsMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "FPS", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for value in Prefs.fpsChoices {
            let item = NSMenuItem(title: "\(value)", action: #selector(setFPS(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = value == Prefs.fps ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    private func sizeMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for value in Prefs.sizeChoices {
            let item = NSMenuItem(title: "\(value)%", action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = value == Prefs.sizePercent ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    private func qualityMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Quality", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for quality in Quality.allCases {
            let item = NSMenuItem(title: quality.label, action: #selector(setQuality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = quality.rawValue
            item.state = quality == Prefs.quality ? .on : .off
            sub.addItem(item)
        }
        parent.submenu = sub
        return parent
    }

    private func outputMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Save GIFs", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        let next = NSMenuItem(title: "Next to Original", action: #selector(setOutputMode(_:)),
                              keyEquivalent: "")
        next.target = self
        next.representedObject = OutputMode.nextToOriginal.rawValue
        next.state = Prefs.outputMode == .nextToOriginal ? .on : .off
        sub.addItem(next)

        let ask = NSMenuItem(title: "Ask Each Time", action: #selector(setOutputMode(_:)),
                             keyEquivalent: "")
        ask.target = self
        ask.representedObject = OutputMode.askEachTime.rawValue
        ask.state = Prefs.outputMode == .askEachTime ? .on : .off
        sub.addItem(ask)

        // Show the currently chosen folder (if any) as a checked, non-clickable item.
        if !Prefs.customFolderPath.isEmpty {
            let path = (Prefs.customFolderPath as NSString).abbreviatingWithTildeInPath
            let current = NSMenuItem(title: path, action: nil, keyEquivalent: "")
            current.state = Prefs.outputMode == .customFolder ? .on : .off
            sub.addItem(current)
        }

        let choose = NSMenuItem(title: "Choose Folder…", action: #selector(chooseFolderAction),
                                keyEquivalent: "")
        choose.target = self
        sub.addItem(choose)

        parent.submenu = sub
        return parent
    }

    private func summaryLine() -> String {
        let destination: String
        switch Prefs.outputMode {
        case .nextToOriginal:
            destination = "next to original"
        case .askEachTime:
            destination = "ask each time"
        case .customFolder:
            let name = (Prefs.customFolderPath as NSString).lastPathComponent
            destination = name.isEmpty ? "ask each time" : "saved to \(name)"
        }
        return "\(Prefs.fps) fps · \(Prefs.sizePercent)% · \(Prefs.quality.rawValue) quality · \(destination)"
    }

    // MARK: Settings actions
    @objc private func setFPS(_ sender: NSMenuItem) {
        Prefs.fps = sender.tag
        rebuildMenu()
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        Prefs.sizePercent = sender.tag
        rebuildMenu()
    }

    @objc private func setQuality(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let quality = Quality(rawValue: raw) {
            Prefs.quality = quality
        }
        rebuildMenu()
    }

    @objc private func setOutputMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = OutputMode(rawValue: raw) {
            Prefs.outputMode = mode
        }
        rebuildMenu()
    }

    @objc private func chooseFolderAction() {
        if let dir = askForOutputFolder() {
            Prefs.customFolderPath = dir.path
            Prefs.outputMode = .customFolder
        }
        rebuildMenu()
    }

    // MARK: Actions
    @objc private func convertAction() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose screen recording(s) to convert to GIF"
        panel.prompt = "Convert"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        convert(urls: panel.urls)
    }

    @objc private func revealAction() {
        guard !lastOutputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(lastOutputs)
    }

    @objc private func ffmpegHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ffmpeg is required"
        alert.informativeText = """
            Gifford uses ffmpeg to convert recordings.

            Install it with Homebrew:

                brew install ffmpeg

            Then reopen this menu — it will pick it up automatically.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Copy install command")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
        }
        ffmpegPath = Self.locateFFmpeg()   // re-check in case they just installed it
        rebuildMenu()
    }

    // MARK: Conversion
    private func askForOutputFolder() -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose where to save the GIF(s)"
        panel.prompt = "Save Here"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// Resolves the destination directory for this batch, or nil for "next to the original".
    /// Returns false if the user cancelled (abort the batch).
    private func resolveDestination(_ destination: inout URL?) -> Bool {
        switch Prefs.outputMode {
        case .nextToOriginal:
            return true
        case .askEachTime:
            guard let dir = askForOutputFolder() else { return false }
            destination = dir
            return true
        case .customFolder:
            var isDir: ObjCBool = false
            let path = Prefs.customFolderPath
            if !path.isEmpty,
               FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
               isDir.boolValue {
                destination = URL(fileURLWithPath: path, isDirectory: true)
                return true
            }
            // The saved folder is gone — fall back to asking rather than failing silently.
            guard let dir = askForOutputFolder() else { return false }
            destination = dir
            return true
        }
    }

    private static func outputURL(for input: URL, in directory: URL?) -> URL {
        // Next to the original: keep the historical behavior of overwriting our own output.
        guard let directory else {
            return input.deletingPathExtension().appendingPathExtension("gif")
        }
        // Elsewhere: never clobber an existing file — append " 2", " 3", … on collision.
        let base = input.deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(base).appendingPathExtension("gif")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n)").appendingPathExtension("gif")
            n += 1
        }
        return candidate
    }

    private func convert(urls: [URL]) {
        guard let ffmpeg = ffmpegPath else { ffmpegHelp(); return }

        var destinationDir: URL? = nil   // nil = next to the original
        guard resolveDestination(&destinationDir) else { return }   // cancel aborts the batch

        let filterComplex = Prefs.filterComplex   // snapshot settings for the whole batch
        isConverting = true
        rebuildMenu()

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var outputs: [URL] = []
            var failures: [(name: String, reason: String)] = []

            for (idx, url) in urls.enumerated() {
                DispatchQueue.main.async {
                    self.statusItem.button?.title = urls.count > 1 ? " \(idx + 1)/\(urls.count)" : " …"
                }
                let out = Self.outputURL(for: url, in: destinationDir)
                switch Self.runFFmpeg(ffmpeg: ffmpeg, input: url, output: out,
                                      filterComplex: filterComplex) {
                case .success:            outputs.append(out)
                case .failure(let msg):   failures.append((url.lastPathComponent, msg))
                }
            }

            DispatchQueue.main.async {
                self.statusItem.button?.title = ""
                self.isConverting = false
                self.lastOutputs = outputs
                self.rebuildMenu()

                if !outputs.isEmpty {
                    NSSound(named: "Glass")?.play()
                    NSWorkspace.shared.activateFileViewerSelecting(outputs)
                }
                if !failures.isEmpty {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = failures.count == 1
                        ? "Couldn’t convert 1 recording"
                        : "Couldn’t convert \(failures.count) recordings"
                    alert.informativeText = failures.map { "• \($0.name): \($0.reason)" }.joined(separator: "\n")
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private enum ConvertResult { case success; case failure(String) }

    private static func runFFmpeg(ffmpeg: String, input: URL, output: URL,
                                  filterComplex: String) -> ConvertResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ffmpeg)
        proc.arguments = ["-y", "-hide_banner", "-loglevel", "error",
                          "-i", input.path,
                          "-filter_complex", filterComplex,
                          output.path]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = FileHandle.nullDevice
        do {
            try proc.run()
            // Read stderr to EOF first (drains the pipe), then wait — avoids a full-pipe deadlock.
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 { return .success }
            let err = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let tail = err.split(separator: "\n").suffix(2).joined(separator: " ")
            return .failure(tail.isEmpty ? "ffmpeg exited with code \(proc.terminationStatus)" : tail)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func locateFFmpeg() -> String? {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return hit
        }
        // Fall back to a login shell's PATH in case ffmpeg lives somewhere custom.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v ffmpeg"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        } catch {}
        return nil
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
