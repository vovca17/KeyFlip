import AppKit
import ServiceManagement

/// Local-only releases. Update paths are embedded at build time, never downloaded.
enum LocalUpdater {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
    static let installedURL = URL(fileURLWithPath: "/Applications/KeyFlip.app")
    static var isInstalled: Bool { Bundle.main.bundleURL.standardizedFileURL == installedURL }

    static func error(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "KeyFlip"
        alert.informativeText = message
        alert.runModal()
    }

    static func installOrUpdate() {
        let current = Bundle.main
        let candidate: URL
        if !isInstalled {
            candidate = current.bundleURL
        } else {
            guard let path = current.object(forInfoDictionaryKey: "KSLocalUpdatePath") as? String else {
                error("Папка локальных обновлений не настроена."); return
            }
            candidate = URL(fileURLWithPath: path)
        }
        guard let data = try? Data(contentsOf: candidate.appendingPathComponent("Contents/Info.plist")),
              let release = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              release["CFBundleIdentifier"] as? String == current.bundleIdentifier else {
            error("Новой сборки пока нет. После изменения программы собери её командой bash scripts/build.sh."); return
        }
        if isInstalled {
            let proposed = Int(release["CFBundleVersion"] as? String ?? "0") ?? 0
            let running = Int(current.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
            guard proposed > running else { error("Установлена последняя локальная сборка: \(version)."); return }
        }
        guard let requirement = current.object(forInfoDictionaryKey: "KSSigningRequirement") as? String,
              let helper = current.url(forResource: "update-app", withExtension: "sh") else {
            error("В этой сборке отсутствует установщик."); return
        }
        do {
            let verification = Process()
            verification.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            verification.arguments = ["--verify", "--deep", "--strict", "-R", requirement, candidate.path]
            verification.standardOutput = FileHandle.nullDevice
            verification.standardError = FileHandle.nullDevice
            try verification.run()
            verification.waitUntilExit()
            guard verification.terminationStatus == 0 else { error("Подпись обновления не прошла проверку. Установка отменена."); return }
            guard FileManager.default.isWritableFile(atPath: installedURL.deletingLastPathComponent().path) else {
                error("Нет прав записи в /Applications. Установи приложение из DMG через Finder."); return
            }
            // Run the helper from a separate location so replacing the bundle cannot remove it.
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("KeyboardSwitcher-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            let script = temporary.appendingPathComponent("update-app.sh")
            try FileManager.default.copyItem(at: helper, to: script)
            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [script.path, candidate.path, installedURL.path, String(ProcessInfo.processInfo.processIdentifier), requirement]
            try updater.run()
            NSApp.terminate(nil)
        } catch { self.error("Не удалось запустить обновление: \(error.localizedDescription)") }
    }

    static func toggleLogin() {
        guard isInstalled else { error("Сначала установи приложение в /Applications."); return }
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { self.error("Не удалось изменить автозапуск: \(error.localizedDescription)") }
    }
}
