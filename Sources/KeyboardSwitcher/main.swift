import AppKit
import ApplicationServices
import Carbon
import SwitcherCore
import ServiceManagement
import IOKit.hidsystem

private let replacementEventTag: Int64 = 0x4B535749

final class TextAccess {
    static var failure = ""
    static func prepare(_ pid: pid_t) {
        let application = AXUIElementCreateApplication(pid)
        // Electron exposes its complete accessibility tree after this opt-in.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
    struct Snapshot {
        let element: AXUIElement
        let value: String
        let selection: NSRange
    }

    static func snapshot() -> Snapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) != .success {
            AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        }
        guard let focused else { failure = "Нет активного поля Accessibility"; return nil }
        let element = focused as! AXUIElement
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &role)
        guard (role as? String) != "AXSecureTextField" else { return nil }
        var value: CFTypeRef?
        var range: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range)
        guard rangeResult == .success, let range, CFGetTypeID(range) == AXValueGetTypeID() else {
            failure = "Поле не отдаёт курсор (AX \(rangeResult.rawValue))"
            return nil
        }
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        if !(value is String) {
            var count: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXNumberOfCharactersAttribute as CFString, &count) == .success,
               let length = count as? Int, length >= 0, length < 1_000_000 {
                var fullRange = CFRange(location: 0, length: length)
                if let parameter = AXValueCreate(.cfRange, &fullRange) {
                    AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value)
                }
            }
        }
        guard let text = value as? String else { failure = "Поле не отдаёт текст (AXValue / AXStringForRange)"; return nil }
        var selected = CFRange()
        guard AXValueGetValue(range as! AXValue, .cfRange, &selected),
              selected.location >= 0, selected.length >= 0,
              selected.location + selected.length <= (text as NSString).length else { return nil }
        return Snapshot(element: element, value: text,
                        selection: NSRange(location: selected.location, length: selected.length))
    }

    static func setRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var range = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }

    enum Method { case direct, keyboard }

    /// Chromium and Electron accept AXSelectedText writes, but page scripts (React and
    /// friends) never see an input event and restore the old text. Type there instead.
    static func prefersKeyboard(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if let cached = chromiumCache[pid] { return cached }
        let browsers: Set<String> = ["com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac",
                                     "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
                                     "ru.yandex.desktop.yandex-browser", "org.chromium.Chromium"]
        var result = browsers.contains(app.bundleIdentifier ?? "")
        if !result, let url = app.bundleURL {
            result = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        }
        chromiumCache[pid] = result
        return result
    }
    private static var chromiumCache: [pid_t: Bool] = [:]

    static func replace(_ snapshot: Snapshot, range: NSRange, with text: String) -> Method? {
        var writable = DarwinBoolean(false)
        if prefersKeyboard(snapshot.element) ||
            AXUIElementIsAttributeSettable(snapshot.element, kAXSelectedTextAttribute as CFString, &writable) != .success || !writable.boolValue {
            return insertThroughKeyboard(snapshot, range: range, text: text) ? .keyboard : nil
        }
        guard setRange(range, on: snapshot.element) else { return nil }
        if AXUIElementSetAttributeValue(snapshot.element, kAXSelectedTextAttribute as CFString, text as CFString) != .success {
            guard setRange(snapshot.selection, on: snapshot.element) else { return nil }
            return insertThroughKeyboard(snapshot, range: range, text: text) ? .keyboard : nil
        }
        // Keep trailing whitespace and the caret after it when correcting the preceding word.
        let delta = (text as NSString).length - range.length
        let caret = snapshot.selection.length > 0 ? range.location + (text as NSString).length : snapshot.selection.location + delta
        _ = setRange(NSRange(location: caret, length: 0), on: snapshot.element)
        return .direct
    }

    /// Chromium fields can expose a selection without allowing AXSelectedText writes.
    /// Select only a verified range, then insert Unicode without touching the clipboard.
    static func insertThroughKeyboard(_ original: Snapshot, range: NSRange, text: String) -> Bool {
        guard !IsSecureEventInputEnabled(), let current = snapshot(),
              CFEqual(current.element, original.element), current.value == original.value,
              current.selection == original.selection else { return false }
        var target = range
        var insertion = text
        if original.selection.length == 0 {
            let gap = original.selection.location - NSMaxRange(range)
            guard gap >= 0 else { return false }
            // The gap is the separator plus anything typed since; retype it unchanged on one line.
            let suffix = (original.value as NSString).substring(with: NSRange(location: NSMaxRange(range), length: gap))
            guard gap <= 120, !suffix.contains(where: \.isNewline) else { return false }
            target.length += gap
            insertion += suffix
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(original.element, &pid) == .success,
              setRange(target, on: original.element) else { return false }
        var selected = snapshot()
        for _ in 0..<6 where selected?.selection != target {
            usleep(10_000)
            selected = snapshot()
        }
        guard let selected, CFEqual(selected.element, original.element),
              selected.value == original.value, selected.selection == target else {
            _ = setRange(original.selection, on: original.element)
            return false
        }
        // A keyboard event carries at most 20 UTF-16 units; split on character boundaries.
        var chunks: [[UniChar]] = [[]]
        for character in insertion {
            let units = Array(String(character).utf16)
            if chunks[chunks.count - 1].count + units.count > 20 { chunks.append([]) }
            chunks[chunks.count - 1] += units
        }
        for units in chunks where !units.isEmpty {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { return false }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: replacementEventTag)
                units.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
                event.postToPid(pid)
            }
        }
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var status: NSStatusItem!
    var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var token = ""
    private var generation = 0
    var paused = false
    private var monitor: Any?
    private var mouseMonitor: Any?
    private var permissionTimer: Timer?
    var lastResult = "Проверка ввода ещё не выполнялась"
    private var rightOption = RightOptionGesture()
    private var mistakes = MistakeTracker()
    private var exceptionPopover: NSPopover?
    private var pendingException: String?
    private var recordingShortcut = false
    private var settings: SettingsWindowController?
    var requiredWords: Set<String> {
        get { Set(defaults.stringArray(forKey: "requiredWords") ?? ["крч"]) }
        set { defaults.set(Array(newValue).sorted(), forKey: "requiredWords") }
    }
    var wordExceptions: Set<String> {
        get { Set((defaults.stringArray(forKey: "wordExceptions") ?? []).map { $0.lowercased() }) }
        set { defaults.set(Array(newValue).sorted(), forKey: "wordExceptions") }
    }
    var modifierShortcut: Shortcut? {
        let id = defaults.string(forKey: "shortcut") ?? "rightOption"
        return Shortcut.choices.first { $0.id == id }
    }
    var shortcutTitle: String {
        modifierShortcut?.title ?? defaults.string(forKey: "shortcutTitle") ?? "⌥Space"
    }
    private struct Replacement {
        let element: AXUIElement
        let start: Int
        let before: String
        let after: String
        let caret: Int
        let automatic: Bool
        let method: TextAccess.Method
    }
    private var replacement: Replacement?
    /// Words finished with a space that wait for a short check; `tail` is what was typed after them.
    private struct PendingWord { let id: Int; let word: String; var tail: String; let pid: pid_t }
    private var pending: [PendingWord] = []
    private var pendingID = 0
    let defaults = UserDefaults.standard
    let spell = NSSpellChecker.shared
    var exclusions: Set<String> {
        get { Set(defaults.stringArray(forKey: "exclusions") ?? ["com.apple.Terminal", "com.googlecode.iterm2"]) }
        set { defaults.set(Array(newValue).sorted(), forKey: "exclusions") }
    }
    /// Remembers the keyboard layout last used in each application.
    var perAppLayout: Bool {
        get { defaults.object(forKey: "perAppLayout") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "perAppLayout") }
    }
    private var appLayouts: [String: String] {
        get { defaults.dictionary(forKey: "appLayouts") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "appLayouts") }
    }
    private var layoutObserver: Any?

    func rememberLayout() {
        guard perAppLayout, let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              id != Bundle.main.bundleIdentifier, !exclusions.contains(id),
              let layout = Self.currentInputID() else { return }
        var layouts = appLayouts
        guard layouts[id] != layout else { return }
        if layouts.count >= 200, layouts[id] == nil { layouts.removeAll() }
        layouts[id] = layout
        appLayouts = layouts
    }

    func restoreLayout(for app: NSRunningApplication) {
        guard perAppLayout, let id = app.bundleIdentifier, !exclusions.contains(id),
              let layout = appLayouts[id], layout != Self.currentInputID() else { return }
        selectInput(ids: [layout])
    }

    @objc func togglePerAppLayout() { perAppLayout.toggle(); if perAppLayout { rememberLayout() }; rebuildMenu() }

    var automatic: Bool {
        get { defaults.object(forKey: "automatic") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "automatic") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid two copies processing the same keystrokes.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        rightOption = RightOptionGesture(keyCode: modifierShortcut?.keyCode ?? 61)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        monitor = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.reset()
                if let app = NSWorkspace.shared.frontmostApplication {
                    TextAccess.prepare(app.processIdentifier)
                    self?.restoreLayout(for: app)
                }
                self?.rebuildMenu()
            }
        if let app = NSWorkspace.shared.frontmostApplication { TextAccess.prepare(app.processIdentifier) }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main) { [weak self] _ in
                self?.rememberLayout()
            }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.reset() }
        rebuildMenu()
        if AXIsProcessTrusted() { start() }
        else {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                self?.start()
            }
            showPermissions()
        }
    }

    func reset() { token = ""; generation += 1; pending.removeAll(); rightOption.cancel() }

    func menuWillOpen(_ menu: NSMenu) {
        // The status menu does not activate KeyFlip, so the frontmost app is the one the user works in.
        guard let item = menu.items.first(where: { $0.tag == 103 }) else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if let front, let id = front.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            item.title = "Выключить в «\(front.localizedName ?? id)»"
            item.representedObject = id
            item.state = exclusions.contains(id) ? .on : .off
            item.isHidden = false
        } else { item.isHidden = true }
    }

    func rebuildMenu() {
        status.button?.title = tap == nil ? "⇄ !" : (paused ? "⇄ ·" : "⇄")
        status.button?.toolTip = "KeyFlip · " + shortcutTitle
        let menu = NSMenu()
        menu.delegate = self
        add("Автоисправление", action: #selector(toggleAuto), state: automatic, to: menu)
        add("Пауза", action: #selector(togglePause), state: paused, to: menu)
        let app = add("Выключить в этом приложении", action: #selector(toggleFrontmostExclusion), to: menu)
        app.tag = 103
        menu.addItem(.separator())
        let preferences = add("Настройки…", action: #selector(openSettings), to: menu)
        preferences.keyEquivalent = ","
        add(LocalUpdater.isInstalled ? "Установить обновление…" : "Установить в Программы…", action: #selector(updateApp), to: menu)
        add("О KeyFlip", action: #selector(about), to: menu)
        menu.addItem(.separator())
        add("Выйти из KeyFlip", action: #selector(quit), to: menu)
        status.menu = menu
        settings?.refresh()
    }

    @discardableResult
    func add(_ title: String, action: Selector? = nil, state: Bool = false, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = state ? .on : .off
        menu.addItem(item)
        return item
    }

    @objc func toggleAuto() { automatic.toggle(); reset(); rebuildMenu() }
    @objc func togglePause() { paused.toggle(); reset(); rebuildMenu() }
    @objc func toggleFrontmostExclusion(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        setExcluded(id, !exclusions.contains(id))
    }
    func setExcluded(_ id: String, _ excluded: Bool) {
        var items = exclusions
        if excluded { items.insert(id) } else { items.remove(id) }
        exclusions = items
        settingsChanged()
    }
    func settingsChanged() { reset(); rebuildMenu() }
    @objc func openSettings() { showSettings(.general) }
    func showSettings(_ tab: SettingsWindowController.Tab) {
        if settings == nil { settings = SettingsWindowController(app: self) }
        settings?.show(tab)
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func updateApp() { LocalUpdater.installOrUpdate() }
    @objc func toggleLogin() { LocalUpdater.toggleLogin(); rebuildMenu() }
    @objc func connect() {
        reset()
        if let source { CFRunLoopSourceInvalidate(source) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if AXIsProcessTrusted() { start() } else { showPermissions() }
        rebuildMenu()
    }
    @objc func about() { showSettings(.about) }
    func showPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        let alert = NSAlert()
        alert.messageText = "Разреши управление клавиатурой"
        alert.informativeText = "Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → KeyFlip. Если macOS запросит «Мониторинг ввода», разреши и его. Затем выбери «Разрешения / подключить заново…» в меню ⇄ или перезапусти приложение."
        alert.runModal()
    }

    func start() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); rebuildMenu(); return }
        // macOS can silently remove keyboard bits from a mixed mouse/keyboard mask.
        // A keyboard-only request cannot masquerade as a working mouse-only tap.
        let keyboardMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let mask = keyboardMask | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                let consumed = DispatchQueue.main.sync { app.handle(type, event: event) }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let tap {
            var count: UInt32 = 0
            if CGGetEventTapList(0, nil, &count) == .success, count > 0 {
                var entries = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
                if CGGetEventTapList(count, &entries, &count) == .success,
                   !entries.prefix(Int(count)).contains(where: { $0.tappingProcess == getpid() && $0.eventsOfInterest & keyboardMask != 0 }) {
                    CFMachPortInvalidate(tap)
                    self.tap = nil
                    lastResult = "macOS исключила клавиши: нужен Input Monitoring"
                    rebuildMenu()
                    return
                }
            }
            guard let eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CFMachPortInvalidate(tap)
                self.tap = nil
                lastResult = "Не удалось создать цикл приёма событий"
                rebuildMenu()
                return
            }
            source = eventSource
            let worker = Thread {
                // AppKit owns the main run loop. Drain the Quartz source independently.
                guard CFMachPortIsValid(tap), CFRunLoopSourceIsValid(eventSource) else { return }
                CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource, .defaultMode)
                CGEvent.tapEnable(tap: tap, enable: true)
                CFRunLoopRun()
            }
            worker.name = "KeyboardSwitcher.events"
            worker.start()
        } else {
            lastResult = "macOS отклонила перехват клавиш"
            if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
            let alert = NSAlert()
            alert.messageText = "Не удалось подключить клавиатуру"
            alert.informativeText = "macOS не разрешила получать клавиши. Открой System Settings → Privacy & Security → Input Monitoring. Удали старую запись KeyFlip кнопкой − и добавь текущую сборку через +. После включения перезапусти приложение. Accessibility и Input Monitoring — отдельные разрешения."
            alert.runModal()
        }
        rebuildMenu()
    }

    func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == replacementEventTag { return false }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reset()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        if type == .flagsChanged {
            let flags = event.flags
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            guard !recordingShortcut, let binding = modifierShortcut else { rightOption.cancel(); return false }
            let other = flags.rawValue & (UInt64(0xFE) | 0x2001) & ~binding.deviceMask != 0 ||
                flags.rawValue & UInt64(0x9E0000) & ~binding.modifierMask != 0
            if rightOption.changed(keyCode: key, rightDown: flags.rawValue & binding.deviceMask != 0, otherModifiers: other) {
                guard !paused, !IsSecureEventInputEnabled(), let app = NSWorkspace.shared.frontmostApplication,
                      !exclusions.contains(app.bundleIdentifier ?? "") else { return false }
                queueManual(pid: app.processIdentifier)
            }
            return false
        }
        guard type == .keyDown else { reset(); return false }
        rightOption.cancel()
        guard !recordingShortcut else { return false }
        generation += 1
        let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if IsSecureEventInputEnabled() { lastResult = "Защищённый ввод блокирует исправление" }
        guard !paused, !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication,
              !exclusions.contains(app.bundleIdentifier ?? "") else { reset(); return false }
        if matchesShortcut(key: key, flags: flags) {
            reset()
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                queueManual(pid: app.processIdentifier)
            }
            return true
        }
        replacement = nil
        guard automatic, flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty else { reset(); return false }
        if key == 49 {
            lastResult = "Пробел получен; ожидается обработка поля"
            appendToPending(" ")
            let word = token
            token = ""
            guard !word.isEmpty else { return false }
            pendingID += 1
            let id = pendingID
            pending.append(PendingWord(id: id, word: word, tail: "", pid: app.processIdentifier))
            // Typing may continue: the check locates the word behind the newly typed tail.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in self?.runPending(id) }
            return false
        }
        if key == 51 {
            if !token.isEmpty { token.removeLast() }
            else {
                // Erasing the space or the tail: drop checks whose separator is gone.
                pending = pending.compactMap { item in
                    guard !item.tail.isEmpty else { return nil }
                    var item = item
                    item.tail.removeLast()
                    return item
                }
            }
            return false
        }
        // Navigation, Enter, Tab, Escape and forward-delete invalidate the word buffer.
        var units = [UniChar](repeating: 0, count: 16)
        var count = 0
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &count, unicodeString: &units)
        let text = String(utf16CodeUnits: units, count: count)
        guard ![36, 48, 53, 76, 117, 115, 119, 116, 121, 123, 124, 125, 126].contains(key), !text.isEmpty,
              text.allSatisfy({ $0.isLetter || $0.isNumber || "[];',.`\"@_+-٪%".contains($0) }), token.count + text.count <= 254 else { reset(); return false }
        token += text
        appendToPending(text)
        return false
    }

    func appendToPending(_ text: String) {
        pending = pending.compactMap { item in
            var item = item
            item.tail += text
            return item.tail.count <= 80 ? item : nil
        }
    }

    func runPending(_ id: Int) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else {
            lastResult = "Проверка отменена: курсор, фокус или текст изменились"
            return
        }
        let item = pending.remove(at: index)
        guard !paused, automatic, NSWorkspace.shared.frontmostApplication?.processIdentifier == item.pid else {
            lastResult = "Проверка отменена: фокус изменился"
            return
        }
        correct(item.word, tail: item.tail)
    }

    func queueManual(pid: pid_t) {
        reset()
        let version = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == version, !self.paused,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self.manual()
        }
    }

    func replaceRemembering(_ snapshot: TextAccess.Snapshot, range: NSRange, old: String, new: String, automatic: Bool = false) -> Bool {
        guard let method = TextAccess.replace(snapshot, range: range, with: new) else { return false }
        let caret = snapshot.selection.length > 0 ? range.location + (new as NSString).length : snapshot.selection.location + (new as NSString).length - range.length
        let record = Replacement(element: snapshot.element, start: range.location, before: old, after: new, caret: caret, automatic: automatic, method: method)
        replacement = record
        verify(record)
        return true
    }

    /// Some fields report success but ignore the edit, or process injected keys later.
    /// Re-read the field and forget an edit that did not land, so undo never touches foreign text.
    private func verify(_ record: Replacement) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, let current = TextAccess.snapshot(), CFEqual(current.element, record.element) else { return }
            let value = current.value as NSString
            let range = NSRange(location: record.start, length: (record.after as NSString).length)
            guard NSMaxRange(range) > value.length || value.substring(with: range) != record.after else {
                self.lastResult = "Замена подтверждена (" + (record.method == .direct ? "Accessibility" : "ввод с клавиатуры") + ")"
                return
            }
            // The field silently reverted a direct write: retry once as typed input.
            let original = NSRange(location: record.start, length: (record.before as NSString).length)
            if record.method == .direct, NSMaxRange(original) <= value.length, value.substring(with: original) == record.before,
               TextAccess.insertThroughKeyboard(current, range: original, text: record.after) {
                let delta = (record.after as NSString).length - original.length
                let caret = current.selection.length > 0 ? record.start + (record.after as NSString).length : current.selection.location + delta
                let retry = Replacement(element: record.element, start: record.start, before: record.before, after: record.after,
                                        caret: caret, automatic: record.automatic, method: .keyboard)
                if let last = self.replacement, last.start == record.start, last.after == record.after { self.replacement = retry }
                self.verify(retry)
                return
            }
            if let last = self.replacement, last.start == record.start, last.after == record.after, CFEqual(last.element, record.element) {
                self.replacement = nil
            }
            self.lastResult = "Поле не подтвердило замену «\(record.before)» → «\(record.after)»"
            if !record.automatic { NSSound.beep() }
            self.rebuildMenu()
        }
    }

    func manual() {
        guard !IsSecureEventInputEnabled(), let snapshot = TextAccess.snapshot() else { NSSound.beep(); return }
        if let previous = replacement, CFEqual(previous.element, snapshot.element), snapshot.selection.length == 0,
           snapshot.selection.location == previous.caret {
            let range = NSRange(location: previous.start, length: (previous.after as NSString).length)
            if NSMaxRange(range) <= (snapshot.value as NSString).length,
               (snapshot.value as NSString).substring(with: range) == previous.after,
               replaceRemembering(snapshot, range: range, old: previous.after, new: previous.before) {
                if previous.automatic, let word = mistakes.recordAutomaticUndo(previous.before) {
                    DispatchQueue.main.async { [weak self] in self?.suggestException(word) }
                }
                selectInput(russian: Layout.isRussian(previous.before))
                lastResult = "Предыдущее изменение возвращено"
                rebuildMenu()
                return
            }
        }
        guard var range = snapshot.selection.length > 0 ? snapshot.selection : Layout.lastWord(in: snapshot.value, before: snapshot.selection.location) else { NSSound.beep(); return }
        var old = (snapshot.value as NSString).substring(with: range)
        if snapshot.selection.length == 0, Layout.emailCandidate(old) == nil {
            // One press fixes the whole mistyped phrase, not only the last word.
            range = Layout.extendLeft(range, in: snapshot.value) { self.looksMistyped($0, like: old) }
            old = (snapshot.value as NSString).substring(with: range)
        }
        let new = Layout.emailCandidate(old) ?? fixCase(Layout.convert(old))
        guard old != new, replaceRemembering(snapshot, range: range, old: old, new: new) else { NSSound.beep(); return }
        selectInput(russian: Layout.isRussian(new))
    }

    /// A preceding word belongs to the phrase when it is in the same script and reads
    /// as a real word only after conversion.
    func looksMistyped(_ word: String, like last: String) -> Bool {
        let russian = Layout.isRussian(word)
        guard russian == Layout.isRussian(last), Layout.convert(word) != word else { return false }
        if ShortWords.candidate(word, allowSingle: true) != nil { return true }
        if Names.candidate(word, additional: Set(defaults.stringArray(forKey: "customNames") ?? [])) != nil,
           known(word, russian: russian) != true { return true }
        let source = Layout.fixInvertedCase(word) ?? word
        guard let candidate = Layout.autoCandidate(source) else { return false }
        return known(source, russian: russian) == false && known(candidate, russian: !russian) == true
    }

    func fixCase(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { Layout.fixInvertedCase(String($0)) ?? String($0) }.joined(separator: " ")
    }

    /// Typing with Caps Lock produced the word; switch Caps Lock off like a human would.
    func capsLockOff() {
        guard CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS else { return }
        defer { IOServiceClose(connect) }
        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), false)
    }

    func known(_ word: String, russian: Bool) -> Bool? {
        let prefix = russian ? "ru" : "en"
        guard let language = spell.availableLanguages.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return spell.checkSpelling(of: word.lowercased(), startingAt: 0, language: language,
                                   wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
    }

    func correct(_ word: String, tail: String = "") {
        defer { rebuildMenu() }
        lastResult = "Пропущено: короткое или неоднозначное слово"
        guard !IsSecureEventInputEnabled() else { return }
        guard !MistakeTracker.isExcluded(word, in: wordExceptions) else {
            lastResult = "Слово находится в исключениях"
            return
        }
        guard !requiredWords.contains(word.lowercased()) else {
            lastResult = "Слово уже записано в правильной раскладке в своём словаре"
            return
        }
        // Caps Lock typing («gHBDTN», «пРИВЕТ») is judged as the normally cased word.
        let caseFixed = Layout.fixInvertedCase(word)
        let source = caseFixed ?? word
        let russian = Layout.isRussian(word)
        let new: String
        if let required = RequiredWords.candidate(source, spellings: requiredWords) { new = required }
        else if let email = Layout.emailCandidate(word) { new = email }
        else if let name = Names.candidate(source, additional: Set(defaults.stringArray(forKey: "customNames") ?? [])),
                known(source, russian: russian) != true { new = name }
        else if let short = ShortWords.candidate(source) { new = short }
        else if let candidate = Layout.autoCandidate(source),
                known(source, russian: russian) == false,
                known(candidate, russian: !russian) == true { new = candidate }
        else if let caseFixed, known(caseFixed, russian: russian) == true { new = caseFixed }
        else { return }
        lastResult = "Поле не предоставляет текст или курсор"
        guard let snapshot = TextAccess.snapshot(), snapshot.selection.length == 0 else {
            lastResult = TextAccess.failure
            if let app = NSWorkspace.shared.frontmostApplication { TextAccess.prepare(app.processIdentifier) }
            return
        }
        lastResult = "Позиция курсора или текст изменились"
        guard var range = TypedWord.range(of: word, tail: tail, in: snapshot.value, caret: snapshot.selection.location) else { return }
        var old = word
        var replacementText = new
        if Layout.isRussian(new) != russian, Layout.emailCandidate(word) == nil {
            // «z rfr ltkf»: one-letter and short words before a mistyped word share its layout.
            let wide = Layout.extendLeft(range, in: snapshot.value, limit: 4) {
                Layout.isRussian($0) == russian && ShortWords.candidate($0, allowSingle: true) != nil &&
                    !MistakeTracker.isExcluded($0, in: self.wordExceptions)
            }
            if wide != range {
                let prefixRange = NSRange(location: wide.location, length: range.location - wide.location)
                let prefix = (snapshot.value as NSString).substring(with: prefixRange)
                old = prefix + word
                replacementText = Layout.convert(prefix) + new
                range = wide
            }
        }
        if replaceRemembering(snapshot, range: range, old: old, new: replacementText, automatic: true) {
            lastResult = "Команда исправления выполнена"
            if caseFixed != nil { capsLockOff() }
            selectInput(russian: Layout.isRussian(new))
        } else { lastResult = "Поле отклонило замену текста" }
    }

    func selectInput(russian: Bool) {
        selectInput(ids: russian ? ["com.apple.keylayout.Russian", "com.apple.keylayout.RussianWin"] : ["com.apple.keylayout.ABC", "com.apple.keylayout.US"])
    }

    static func currentInputID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    func selectInput(ids: [String]) {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
                      kTISPropertyInputSourceIsSelectCapable as String: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        for id in ids {
            if let input = list.first(where: {
                guard let pointer = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
                return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String == id
            }) { TISSelectInputSource(input); return }
        }
    }
}

extension AppDelegate {
    func applyShortcut(_ id: String) {
        defaults.set(id, forKey: "shortcut")
        if id == "optionSpace" { defaults.set("⌥Space", forKey: "shortcutTitle") }
        rightOption = RightOptionGesture(keyCode: modifierShortcut?.keyCode ?? 61)
        settingsChanged()
    }

    func matchesShortcut(key: Int64, flags: CGEventFlags) -> Bool {
        guard modifierShortcut == nil else { return false }
        if defaults.string(forKey: "shortcut") == "custom" {
            return key == Int64(defaults.integer(forKey: "shortcutKey")) && flags.rawValue == UInt64(defaults.integer(forKey: "shortcutFlags"))
        }
        return key == 49 && flags == .maskAlternate
    }

    @objc func recordShortcut() {
        reset()
        recordingShortcut = true
        defer { recordingShortcut = false; reset(); rebuildMenu() }
        let alert = NSAlert()
        alert.messageText = "Нажми своё сочетание"
        alert.informativeText = "Зажми Command, Option или Control и нажми клавишу. Shift можно добавить. Escape — отмена."
        alert.addButton(withTitle: "Отмена")
        var selected: (Int, UInt64, String)?
        let observer = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { NSApp.stopModal(withCode: .cancel); return nil }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
            let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
            let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            selected = (Int(event.keyCode), UInt64(flags.rawValue), symbols + key)
            NSApp.stopModal(withCode: .OK)
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        _ = alert.runModal()
        if let observer { NSEvent.removeMonitor(observer) }
        alert.window.orderOut(nil)
        if let (key, flags, title) = selected {
            defaults.set("custom", forKey: "shortcut")
            defaults.set(key, forKey: "shortcutKey")
            defaults.set(Int(flags), forKey: "shortcutFlags")
            defaults.set(title, forKey: "shortcutTitle")
            rightOption = RightOptionGesture(keyCode: 61)
        }
    }

    func suggestException(_ word: String) {
        guard !wordExceptions.contains(word), let button = status.button else { return }
        exceptionPopover?.close()
        pendingException = word
        let controller = NSViewController()
        let message = NSTextField(wrappingLabelWithString: "Ты уже трижды отменил исправление «\(word)». Больше не менять это слово автоматически?")
        message.preferredMaxLayoutWidth = 300
        let accept = NSButton(title: "Добавить в исключения", target: self, action: #selector(acceptException))
        let dismiss = NSButton(title: "Не сейчас", target: self, action: #selector(dismissException))
        let buttons = NSStackView(views: [accept, dismiss])
        buttons.spacing = 8
        let stack = NSStackView(views: [message, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor), stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor), view.widthAnchor.constraint(equalToConstant: 360)])
        controller.view = view
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 360, height: 160)
        exceptionPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    @objc func acceptException() {
        if let word = pendingException { var words = wordExceptions; words.insert(word); wordExceptions = words }
        dismissException()
    }
    @objc func dismissException() { exceptionPopover?.close(); pendingException = nil }

    var diagnosticsText: String {
        let connected = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        let dictionaries = spell.availableLanguages.filter { $0.hasPrefix("ru") || $0.hasPrefix("en") }.joined(separator: ", ")
        return """
        Accessibility: \(AXIsProcessTrusted() ? "разрешён" : "нет доступа")
        Клавиатура: \(connected ? "подключена" : "не подключена")
        Защищённый ввод: \(IsSecureEventInputEnabled() ? "включён" : "выключен")
        Последняя проверка: \(lastResult)
        Словари: \(dictionaries.isEmpty ? "нет" : dictionaries)
        \(Bundle.main.bundlePath)
        """
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
if let index = CommandLine.arguments.firstIndex(of: "--probe"), index + 1 < CommandLine.arguments.count {
    // Describes the focused field's capabilities only; never records its text.
    var lines = ["trusted: \(AXIsProcessTrusted())"]
    if let front = NSWorkspace.shared.frontmostApplication {
        lines.append("app: \(front.bundleIdentifier ?? "?")")
        let application = AXUIElementCreateApplication(front.processIdentifier)
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused)
        lines.append("focused: \(result.rawValue)")
        if let focused {
            let element = focused as! AXUIElement
            for name in [kAXRoleAttribute, kAXSubroleAttribute] {
                var value: CFTypeRef?
                AXUIElementCopyAttributeValue(element, name as CFString, &value)
                lines.append("\(name): \(value as? String ?? "-")")
            }
            for name in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute, kAXValueAttribute] {
                var writable = DarwinBoolean(false)
                let r = AXUIElementIsAttributeSettable(element, name as CFString, &writable)
                lines.append("settable \(name): \(r.rawValue)/\(writable.boolValue)")
            }
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            lines.append("value type: \(value.map { String(describing: CFGetTypeID($0) == CFStringGetTypeID() ? "string" : "other") } ?? "none")")
        }
    }
    try? lines.joined(separator: "\n").write(toFile: CommandLine.arguments[index + 1], atomically: true, encoding: .utf8)
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-settings"), index + 1 < CommandLine.arguments.count {
    app.setActivationPolicy(.accessory)
    SettingsWindowController(app: delegate).render(to: CommandLine.arguments[index + 1])
    exit(0)
}
if CommandLine.arguments.contains("--diagnostics") {
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Keyboard access: \(CGPreflightListenEventAccess())")
    print("Secure input: \(IsSecureEventInputEnabled())")
    if let snapshot = TextAccess.snapshot() {
        var writable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(snapshot.element, kAXSelectedTextAttribute as CFString, &writable)
        print("Focused text: available; replacement: \(result.rawValue)/\(writable.boolValue)")
    } else { print("Focused text: unavailable") }
    print("Dictionaries: \(NSSpellChecker.shared.availableLanguages.joined(separator: ", "))")
    for word in ["hello", "руддщ", "привет", "ghbdtn"] {
        print("\(word): \(delegate.known(word, russian: Layout.isRussian(word)).map(String.init) ?? "unavailable")")
    }
    exit(0)
}
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
