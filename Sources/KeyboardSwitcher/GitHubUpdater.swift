import AppKit
import CryptoKit
import SwitcherCore

final class GitHubUpdater: NSObject, NSWindowDelegate {
    static let shared = GitHubUpdater()
    private var task: Task<Void, Never>?
    private var panel: NSPanel?
    private var status: NSTextField?
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
    }
    #if arch(arm64)
    static let architecture = "arm64"
    #else
    static let architecture = "x86_64"
    #endif
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    func start() {
        guard task == nil else { panel?.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 125), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Обновление KeyFlip"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let label = NSTextField(wrappingLabelWithString: "Проверяем GitHub Releases…")
        label.frame = NSRect(x: 20, y: 60, width: 360, height: 45)
        let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 28, height: 28))
        indicator.style = .spinning
        indicator.startAnimation(nil)
        let cancel = NSButton(title: "Отмена", target: self, action: #selector(cancelUpdate))
        cancel.frame = NSRect(x: 280, y: 18, width: 100, height: 32)
        panel.contentView?.addSubview(label)
        panel.contentView?.addSubview(indicator)
        panel.contentView?.addSubview(cancel)
        self.panel = panel
        status = label
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var directory: URL?
            var handedOff = false
            defer {
                self.task = nil
                self.panel?.close()
                self.panel = nil
                if !handedOff, let directory { try? FileManager.default.removeItem(at: directory) }
            }
            do {
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                guard let release = try await Self.latest(after: current) else {
                    self.panel?.orderOut(nil)
                    LocalUpdater.error("Установлена последняя доступная версия KeyFlip: \(current).")
                    return
                }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("KeyFlip-download-\(UUID().uuidString)")
                directory = temp
                let app = try await Self.prepare(release, directory: temp) { self.status?.stringValue = $0 }
                try Task.checkCancellation()
                self.status?.stringValue = "Устанавливаем \(release.tag_name)…"
                handedOff = LocalUpdater.installCandidate(app)
            } catch {
                if !Task.isCancelled {
                    self.panel?.orderOut(nil)
                    LocalUpdater.error("Не удалось обновить KeyFlip. Текущая версия сохранена.\n\n\(error.localizedDescription)")
                }
            }
        }
    }
    @objc private func cancelUpdate() { task?.cancel(); panel?.close() }
    func windowWillClose(_ notification: Notification) { task?.cancel() }

    static func latest(after version: String) async throws -> GitHubRelease? {
        let url = URL(string: "https://api.github.com/repos/vovca17/KeyFlip/releases?per_page=100")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("KeyFlip-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try check(response)
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        // Preview releases are intentional while KeyFlip is in the public 0.x testing series.
        return UpdateFeed.select(releases, current: version, architecture: architecture)
    }

    @MainActor
    static func prepare(_ release: GitHubRelease, directory: URL, progress: (String) -> Void) async throws -> URL {
        guard let asset = UpdateFeed.archive(in: release, architecture: architecture),
              let url = URL(string: asset.browser_download_url), let digest = asset.digest,
              digest.hasPrefix("sha256:"), digest.count == 71 else {
            throw Failure.message("В выпуске нет подходящего ZIP с контрольной суммой.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        progress("Загружаем KeyFlip \(release.tag_name)…")
        let (download, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: download) }
        try check(response)
        try Task.checkCancellation()
        let size = (try FileManager.default.attributesOfItem(atPath: download.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size == asset.size, size <= 200_000_000 else { throw Failure.message("Размер загруженного файла не совпадает с выпуском.") }
        let hash = SHA256.hash(data: try Data(contentsOf: download, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == "sha256:" + hash else { throw Failure.message("Контрольная сумма обновления не совпадает.") }
        progress("Проверяем архив и подпись…")
        let paths = try run("/usr/bin/zipinfo", ["-1", download.path])
        guard UpdateFeed.safeArchivePaths(paths) else { throw Failure.message("Неожиданное содержимое архива обновления.") }
        let details = try run("/usr/bin/zipinfo", ["-l", download.path]).split(separator: "\n")
        var unpacked = 0
        guard details.count <= 10000 else { throw Failure.message("Слишком много файлов в архиве.") }
        for line in details {
            guard !line.hasPrefix("l") else { throw Failure.message("Символические ссылки в обновлении не поддерживаются.") }
            let fields = line.split(whereSeparator: \.isWhitespace)
            if line.hasPrefix("-"), fields.count > 3, let bytes = Int(fields[3]) { unpacked += bytes }
        }
        guard unpacked <= 500_000_000 else { throw Failure.message("Архив обновления слишком большой.") }
        _ = try run("/usr/bin/ditto", ["-x", "-k", download.path, directory.path])
        let candidate = directory.appendingPathComponent("KeyFlip.app")
        let data = try Data(contentsOf: candidate.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == String(release.tag_name.dropFirst(release.tag_name.hasPrefix("v") ? 1 : 0)),
              let requirement = Bundle.main.object(forInfoDictionaryKey: "KSSigningRequirement") as? String else {
            throw Failure.message("В архиве находится другое приложение или версия.")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", requirement, candidate.path])
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let currentOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        if let minimum = info["LSMinimumSystemVersion"] as? String,
           minimum.compare(currentOS, options: .numeric) == .orderedDescending {
            throw Failure.message("Обновлению нужна macOS \(minimum) или новее.")
        }
        try Task.checkCancellation()
        return candidate
    }
    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https" else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw Failure.message(code == 403 || code == 429 ? "GitHub временно ограничил запросы. Попробуй позже." : "GitHub недоступен или вернул ошибку \(code).")
        }
    }
    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.message("Проверка или распаковка обновления не прошла: \(URL(fileURLWithPath: executable).lastPathComponent).") }
        return String(decoding: data, as: UTF8.self)
    }
}
