import AppKit
import ServiceManagement
import SwitcherCore

/// Compact preferences window with toolbar tabs, opened from the status menu.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Tab: Int { case general, exclusions, names, dictionary, about }

    private unowned let app: AppDelegate
    private let tabs = NSTabViewController()
    private let general: GeneralPane
    private let exclusions: ExclusionsPane
    private let dictionary: RequiredWordsPane
    private let names: NamesPane
    private let about: AboutPane

    init(app: AppDelegate) {
        self.app = app
        general = GeneralPane(app: app)
        exclusions = ExclusionsPane(app: app)
        names = NamesPane(app: app)
        dictionary = RequiredWordsPane(app: app)
        about = AboutPane(app: app)
        tabs.tabStyle = .toolbar
        for (pane, title, symbol) in [(general as NSViewController, "Основные", "gearshape"),
                                      (exclusions, "Исключения", "nosign"),
                                      (names, "Имена", "person.text.rectangle"),
                                      (dictionary, "Словарь", "book.closed"),
                                      (about, "О программе", "info.circle")] {
            let item = NSTabViewItem(viewController: pane)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    /// Development aid: renders every tab's content to PNG files without showing the window.
    func render(to directory: String) {
        for index in 0..<tabs.tabViewItems.count {
            tabs.selectedTabViewItemIndex = index
            refresh()
            dictionary.load()
            guard let content = window?.contentView else { continue }
            content.layoutSubtreeIfNeeded()
            guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("tab\(index).png"))
        }
    }

    func show(_ tab: Tab = .general) {
        refresh()
        names.load()
        dictionary.load()
        exclusions.loadWords()
        tabs.selectedTabViewItemIndex = tab.rawValue
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Re-reads state that can also change from the status menu. Text editors keep their caret.
    func refresh() {
        guard isWindowLoaded else { return }
        general.refresh()
        exclusions.refresh()
        about.refresh()
    }
}

// MARK: - Building blocks

private func label(_ text: String, secondary: Bool = false, size: CGFloat? = nil) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: text)
    field.isSelectable = false
    if secondary { field.textColor = .secondaryLabelColor }
    field.font = .systemFont(ofSize: size ?? (secondary ? NSFont.smallSystemFontSize : NSFont.systemFontSize))
    return field
}

private func editor(height: CGFloat, delegate: NSTextViewDelegate) -> (NSScrollView, NSTextView) {
    let scroll = NSTextView.scrollableTextView()
    let text = scroll.documentView as! NSTextView
    text.isRichText = false
    text.isAutomaticSpellingCorrectionEnabled = false
    text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.font = .systemFont(ofSize: NSFont.systemFontSize)
    text.textContainerInset = NSSize(width: 4, height: 6)
    text.delegate = delegate
    scroll.borderType = .bezelBorder
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    return (scroll, text)
}

private class Pane: NSViewController {
    unowned let app: AppDelegate
    let stack = NSStackView()
    init(app: AppDelegate) { self.app = app; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            root.widthAnchor.constraint(equalToConstant: 520),
            root.heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor)
        ])
        view = root
        build()
        preferredContentSize = NSSize(width: 520, height: max(stack.fittingSize.height, 200))
    }
    func build() {}
    func add(_ view: NSView, spacingAfter: CGFloat? = nil, fill: Bool = false) {
        stack.addArrangedSubview(view)
        if let spacingAfter { stack.setCustomSpacing(spacingAfter, after: view) }
        if fill { view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true }
    }
}

// MARK: - General

private final class GeneralPane: Pane {
    private let automatic = NSButton(checkboxWithTitle: "Исправлять раскладку автоматически после пробела", target: nil, action: nil)
    private let perApp = NSButton(checkboxWithTitle: "Запоминать раскладку для каждого приложения", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Запускать KeyFlip при входе в систему", target: nil, action: nil)
    private let shortcut = NSPopUpButton()

    override func build() {
        for (button, action) in [(automatic, #selector(toggleAutomatic)), (perApp, #selector(togglePerApp)), (login, #selector(toggleLogin))] {
            button.target = self
            button.action = action
        }
        add(automatic)
        add(label("Слова, короткие слова, имена, почта и случайный Caps Lock. Правильные слова не трогаются.", secondary: true), spacingAfter: 14, fill: true)
        add(perApp)
        add(label("При переходе в программу включается раскладка, в которой ты писал там в прошлый раз.", secondary: true), spacingAfter: 14, fill: true)
        add(login, spacingAfter: 22)

        let title = label("Клавиша исправления", size: NSFont.systemFontSize)
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        add(title, spacingAfter: 8)
        shortcut.target = self
        shortcut.action = #selector(selectShortcut)
        let record = NSButton(title: "Записать своё…", target: self, action: #selector(recordShortcut))
        let row = NSStackView(views: [shortcut, record])
        row.spacing = 8
        add(row)
        add(label("Нажми и отпусти: меняет раскладку последнего слова, фразы или выделения. Сразу после исправления — возвращает как было.", secondary: true), fill: true)
    }

    func refresh() {
        automatic.state = app.automatic ? .on : .off
        perApp.state = app.perAppLayout ? .on : .off
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        shortcut.removeAllItems()
        let current = app.defaults.string(forKey: "shortcut") ?? "rightOption"
        var items = Shortcut.choices.map { ($0.id, $0.title) } + [("optionSpace", "⌥Space")]
        if current == "custom" { items.append(("custom", app.shortcutTitle)) }
        for (id, title) in items {
            shortcut.addItem(withTitle: title)
            shortcut.lastItem?.representedObject = id
            if id == current { shortcut.select(shortcut.lastItem) }
        }
    }

    @objc func toggleAutomatic() { app.automatic = automatic.state == .on; app.settingsChanged() }
    @objc func togglePerApp() { app.togglePerAppLayout() }
    @objc func toggleLogin() { app.toggleLogin() }
    @objc func selectShortcut() {
        guard let id = shortcut.selectedItem?.representedObject as? String, id != "custom" else { return }
        app.applyShortcut(id)
    }
    @objc func recordShortcut() { app.recordShortcut() }
}

// MARK: - Exclusions

private final class ExclusionsPane: Pane, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private let table = NSTableView()
    private let buttons = NSSegmentedControl()
    private var ids: [String] = []
    private var words: NSTextView!

    override func build() {
        let title = label("Приложения, где KeyFlip выключен")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        add(title, spacingAfter: 6)

        let column = NSTableColumn(identifier: .init("app"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 24
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 132).isActive = true
        add(scroll, spacingAfter: 0, fill: true)

        buttons.segmentStyle = .smallSquare
        buttons.trackingMode = .momentary
        buttons.segmentCount = 2
        buttons.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: "Добавить"), forSegment: 0)
        buttons.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Убрать"), forSegment: 1)
        buttons.setWidth(28, forSegment: 0)
        buttons.setWidth(28, forSegment: 1)
        buttons.target = self
        buttons.action = #selector(segment)
        add(buttons, spacingAfter: 4)
        add(label("В этих программах не работают ни автоисправление, ни клавиша исправления.", secondary: true), spacingAfter: 18, fill: true)

        let wordsTitle = label("Слова, которые не исправлять автоматически")
        wordsTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        add(wordsTitle, spacingAfter: 6)
        let (wordsScroll, wordsView) = editor(height: 90, delegate: self)
        words = wordsView
        add(wordsScroll, spacingAfter: 4, fill: true)
        add(label("Одно слово на строку, регистр не важен. Клавиша исправления для них продолжает работать.", secondary: true), fill: true)
    }

    func refresh() {
        let names = Dictionary(uniqueKeysWithValues: app.exclusions.map { ($0, Self.name(of: $0)) })
        ids = names.keys.sorted { names[$0]!.localizedCaseInsensitiveCompare(names[$1]!) == .orderedAscending }
        table.reloadData()
    }

    func loadWords() { words?.string = app.wordExceptions.sorted().joined(separator: "\n") }

    static func name(of id: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first, let name = running.localizedName { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            let known = ["com.googlecode.iterm2": "iTerm2", "com.apple.Terminal": "Terminal"]
            let short = id.split(separator: ".").last.map(String.init) ?? id
            return (known[id] ?? short) + " — не установлено"
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { ids.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = ids[row]
        let cell = NSTableCellView()
        let icon = NSImageView()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { icon.image = NSWorkspace.shared.icon(forFile: url.path) }
        let text = NSTextField(labelWithString: Self.name(of: id))
        text.lineBreakMode = .byTruncatingTail
        let row = NSStackView(views: [icon, text])
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        cell.addSubview(row)
        cell.imageView = icon
        cell.textField = text
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                                     row.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                                     row.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }

    @objc func segment() {
        if buttons.selectedSegment == 1 {
            guard table.selectedRow >= 0 else { NSSound.beep(); return }
            app.setExcluded(ids[table.selectedRow], false)
            return
        }
        // Running apps first, then any app picked from disk.
        let menu = NSMenu()
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier && !app.exclusions.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        for application in running {
            let item = NSMenuItem(title: application.localizedName ?? application.bundleIdentifier!, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = application.bundleIdentifier
            item.image = application.icon.map { icon in
                let copy = icon.copy() as! NSImage
                copy.size = NSSize(width: 16, height: 16)
                return copy
            }
            menu.addItem(item)
        }
        if !running.isEmpty { menu.addItem(.separator()) }
        let other = NSMenuItem(title: "Другое приложение…", action: #selector(chooseFile), keyEquivalent: "")
        other.target = self
        menu.addItem(other)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: buttons.bounds.height + 4), in: buttons)
    }

    @objc func pick(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { app.setExcluded(id, true) }
    }

    @objc func chooseFile() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Исключить"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
            self?.app.setExcluded(id, true)
        }
    }

    func textDidChange(_ notification: Notification) {
        let list = words.string.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }.filter { $0.count <= 254 }
        app.wordExceptions = Set(list)
    }
}

// MARK: - Names

private final class NamesPane: Pane, NSTextViewDelegate {
    private var text: NSTextView!
    private let status = label("", secondary: true)

    override func build() {
        let title = label("Свои имена и фамилии")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        add(title, spacingAfter: 6)
        add(label("Пиши в правильной раскладке, по одному на строку: «владимир», «vladimir». Если такое слово набрано в неверной раскладке, KeyFlip исправит его, даже когда его нет в словаре.", secondary: true), spacingAfter: 10, fill: true)
        let (scroll, view) = editor(height: 200, delegate: self)
        text = view
        add(scroll, spacingAfter: 6, fill: true)
        add(status, fill: true)
    }

    func load() {
        text?.string = (app.defaults.stringArray(forKey: "customNames") ?? []).joined(separator: "\n")
        updateStatus(invalid: [])
    }

    func textDidChange(_ notification: Notification) {
        let entries = text.string.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            .filter { !$0.isEmpty }
        let valid = entries.filter { (2...40).contains($0.count) && $0.allSatisfy(\.isLetter) }
        app.defaults.set(Array(Set(valid.map { $0.lowercased() })).sorted(), forKey: "customNames")
        updateStatus(invalid: entries.filter { !valid.contains($0) })
    }

    private func updateStatus(invalid: [String]) {
        if invalid.isEmpty {
            status.stringValue = "Встроено \(Names.builtIn.count) имён. Изменения сохраняются сразу."
            status.textColor = .secondaryLabelColor
        } else {
            status.stringValue = "Не сохранено (нужны только буквы, 2–40): " + invalid.prefix(3).joined(separator: ", ")
            status.textColor = .systemRed
        }
    }
}

// MARK: - About

private final class AboutPane: Pane {
    private let version = label("")
    private let diagnostics = label("", secondary: true)

    override func build() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = label("KeyFlip", size: 20)
        name.font = .boldSystemFont(ofSize: 20)
        let titles = NSStackView(views: [name, version])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let header = NSStackView(views: [icon, titles])
        header.spacing = 14
        add(header, spacingAfter: 14)
        add(label("Исправляет текст, набранный не в той раскладке: RU ↔ EN, имена, почта, Caps Lock. Работает локально, без сети и без журнала ввода.", secondary: false), spacingAfter: 16, fill: true)

        let diagTitle = label("Диагностика")
        diagTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        add(diagTitle, spacingAfter: 4)
        diagnostics.isSelectable = true
        add(diagnostics, spacingAfter: 16, fill: true)

        let update = NSButton(title: LocalUpdater.isInstalled ? "Установить обновление…" : "Установить в Программы…", target: self, action: #selector(updateApp))
        let reconnect = NSButton(title: "Подключить заново", target: self, action: #selector(reconnect))
        let refreshButton = NSButton(title: "Обновить", target: self, action: #selector(refreshNow))
        let row = NSStackView(views: [update, reconnect, refreshButton])
        row.spacing = 8
        add(row)
    }

    func refresh() {
        version.stringValue = "Версия \(LocalUpdater.version)"
        version.textColor = .secondaryLabelColor
        diagnostics.stringValue = app.diagnosticsText
    }

    @objc func updateApp() { app.updateApp() }
    @objc func reconnect() { app.connect(); refresh() }
    @objc func refreshNow() { refresh() }
}

// MARK: - Mandatory user spellings
private final class RequiredWordsPane: Pane, NSTextViewDelegate {
    private var text: NSTextView!
    private let status = label("", secondary: true)

    override func build() {
        let title = label("Всегда исправлять")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        add(title, spacingAfter: 6)
        add(label("Добавь правильное написание, по одному слову на строку. Например: «крч» — тогда «rhx» после пробела станет «крч», даже если слова нет в системном словаре. Можно добавлять русские и английские слова.", secondary: true), spacingAfter: 10, fill: true)
        let (scroll, view) = editor(height: 180, delegate: self)
        text = view
        add(scroll, spacingAfter: 6, fill: true)
        add(status, fill: true)
        add(label("Сохраняется автоматически. Правильно набранное слово не переключается обратно. Исключения слов, пауза и исключённые приложения имеют приоритет.", secondary: true), fill: true)
    }

    func load() {
        text?.string = app.requiredWords.sorted().joined(separator: "\n")
        updateStatus(invalid: [])
    }

    func textDidChange(_ notification: Notification) {
        let entries = text.string.split(whereSeparator: \.isWhitespace).map(String.init)
        app.requiredWords = Set(entries.compactMap(RequiredWords.normalized))
        updateStatus(invalid: entries.filter { RequiredWords.normalized($0) == nil })
    }

    private func updateStatus(invalid: [String]) {
        status.textColor = invalid.isEmpty ? .secondaryLabelColor : .systemRed
        status.stringValue = invalid.isEmpty ? "Сохранено слов: \(app.requiredWords.count)" : "Не сохранены: \(invalid.prefix(5).joined(separator: ", ")). Нужны 1–40 букв одного алфавита, без цифр и знаков."
    }
}
