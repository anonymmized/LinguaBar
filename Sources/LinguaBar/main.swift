import AppKit
import Carbon.HIToolbox
import Foundation

private struct Language: Equatable, Sendable {
    let name: String
    let shortName: String
    let code: String
}

private let languages: [Language] = [
    Language(name: "Русский", shortName: "RU", code: "ru"),
    Language(name: "English", shortName: "EN", code: "en"),
    Language(name: "Français", shortName: "FR", code: "fr"),
    Language(name: "Italiano", shortName: "IT", code: "it"),
    Language(name: "Español", shortName: "ES", code: "es")
]

@MainActor
private final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let showOnLaunch = "showOnLaunch"
        static let autoHide = "autoHide"
        static let autoTranslate = "autoTranslate"
    }

    private let defaults = UserDefaults.standard

    var showOnLaunch: Bool {
        get { value(for: Key.showOnLaunch, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.showOnLaunch) }
    }

    var autoHide: Bool {
        get { value(for: Key.autoHide, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.autoHide) }
    }

    var autoTranslate: Bool {
        get { value(for: Key.autoTranslate, defaultValue: true) }
        set { defaults.set(newValue, forKey: Key.autoTranslate) }
    }

    private func value(for key: String, defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
    }
}

private final class TranslationService: @unchecked Sendable {
    enum TranslationError: Error {
        case emptyText
        case invalidURL
        case noResult
    }

    private let session: URLSession
    private let fallback = LocalPhrasebook()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }
        guard source != target else { return trimmed }

        if let local = fallback.translate(trimmed, from: source.code, to: target.code) {
            return local
        }

        var components = URLComponents(string: "https://api.mymemory.translated.net/get")
        components?.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "langpair", value: "\(source.code)|\(target.code)")
        ]
        guard let url = components?.url else { throw TranslationError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, _) = try await session.data(for: request)
        let decoded = try JSONDecoder().decode(MyMemoryResponse.self, from: data)
        let result = decoded.responseData.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw TranslationError.noResult }
        return result
    }
}

private struct MyMemoryResponse: Decodable {
    struct ResponseData: Decodable {
        let translatedText: String
    }

    let responseData: ResponseData
}

private final class LocalPhrasebook: Sendable {
    private let entries: [String: [String: String]] = [
        "ru|en": [
            "привет": "hello",
            "доброе утро": "good morning",
            "добрый вечер": "good evening",
            "спасибо": "thank you",
            "пожалуйста": "please",
            "как дела?": "how are you?",
            "до свидания": "goodbye"
        ],
        "en|ru": [
            "hello": "привет",
            "good morning": "доброе утро",
            "good evening": "добрый вечер",
            "thank you": "спасибо",
            "please": "пожалуйста",
            "how are you?": "как дела?",
            "goodbye": "до свидания"
        ],
        "en|fr": [
            "hello": "bonjour",
            "thank you": "merci",
            "please": "s'il vous plaît",
            "goodbye": "au revoir"
        ],
        "en|it": [
            "hello": "ciao",
            "thank you": "grazie",
            "please": "per favore",
            "goodbye": "arrivederci"
        ],
        "en|es": [
            "hello": "hola",
            "thank you": "gracias",
            "please": "por favor",
            "goodbye": "adiós"
        ]
    ]

    func translate(_ text: String, from source: String, to target: String) -> String? {
        let key = "\(source)|\(target)"
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return entries[key]?[normalized]
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let translator = TranslationService()
    private let settings = AppSettings.shared
    private var windowController: TranslatorWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("LinguaBar: applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerHotKey()

        if settings.showOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.showTranslator()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        if settings.autoHide {
            hideTranslator()
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.title = ""
            button.image = makeMenuBarLogo()
            button.imagePosition = .imageOnly
            button.action = #selector(toggleTranslator)
            button.target = self
            button.toolTip = "LinguaBar Translator"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            NSLog("LinguaBar: status item configured")
        }
    }

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: fourCharCode("LNGB"), id: 1)
        let modifiers = UInt32(cmdKey | optionKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_T),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            NSLog("LinguaBar: failed to register hotkey, status \(status)")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }

                var hotKeyID = EventHotKeyID()
                let error = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard error == noErr, hotKeyID.id == 1 else { return noErr }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    appDelegate.toggleTranslator()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    @objc private func toggleTranslator() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }

        if let window = windowController?.window, window.isVisible {
            hideTranslator()
        } else {
            showTranslator()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let visibilityTitle = windowController?.window?.isVisible == true ? "Скрыть переводчик" : "Открыть переводчик"
        menu.addItem(NSMenuItem(title: visibilityTitle, action: #selector(toggleTranslatorFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из LinguaBar", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleTranslatorFromMenu() {
        if let window = windowController?.window, window.isVisible {
            hideTranslator()
        } else {
            showTranslator()
        }
    }

    @objc private func showTranslator() {
        if windowController == nil {
            windowController = TranslatorWindowController(translator: translator, settings: settings)
        }

        guard let controller = windowController, let button = statusItem.button else { return }
        controller.show(relativeTo: button.window)
    }

    @objc private func hideTranslator() {
        windowController?.close()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
        }

        settingsWindowController?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeMenuBarLogo() -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22))
        image.lockFocus()

        let outer = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 3, width: 17, height: 16), xRadius: 5, yRadius: 5)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        outer.lineWidth = 1.8
        outer.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 7, y: 3.4))
        tail.line(to: NSPoint(x: 5.2, y: 0.9))
        tail.line(to: NSPoint(x: 10.2, y: 3.2))
        NSColor.white.withAlphaComponent(0.95).setStroke()
        tail.lineWidth = 1.8
        tail.lineJoinStyle = .round
        tail.stroke()

        let a = NSBezierPath()
        a.move(to: NSPoint(x: 7.4, y: 7))
        a.line(to: NSPoint(x: 10.4, y: 15))
        a.line(to: NSPoint(x: 13.5, y: 7))
        a.move(to: NSPoint(x: 8.7, y: 10.2))
        a.line(to: NSPoint(x: 12.2, y: 10.2))
        NSColor.white.withAlphaComponent(0.95).setStroke()
        a.lineWidth = 1.65
        a.lineCapStyle = .round
        a.lineJoinStyle = .round
        a.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}

@MainActor
private final class TranslatorWindowController: NSWindowController {
    private let translator: TranslationService
    private let settings: AppSettings
    private let sourcePopup = NSPopUpButton()
    private let targetPopup = NSPopUpButton()
    private let inputView = NSTextView()
    private let outputView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "Готово")
    private let translateButton = NSButton(title: "Перевести", target: nil, action: nil)
    private let swapButton = NSButton(title: "⇄", target: nil, action: nil)
    private let copyButton = NSButton(title: "Скопировать", target: nil, action: nil)
    private var translateTask: Task<Void, Never>?

    init(translator: TranslationService, settings: AppSettings) {
        self.translator = translator
        self.settings = settings
        let contentSize = NSSize(width: 390, height: 246)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LinguaBar"
        window.isReleasedWhenClosed = false
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.hidesOnDeactivate = settings.autoHide
        window.isFloatingPanel = true
        window.minSize = contentSize
        window.maxSize = contentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        super.init(window: window)
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo anchorWindow: NSWindow?) {
        guard let window else { return }

        if let anchorWindow, let screen = anchorWindow.screen {
            let visible = screen.visibleFrame
            let frame = NSRect(
                x: visible.maxX - window.frame.width - 18,
                y: visible.maxY - window.frame.height - 14,
                width: window.frame.width,
                height: window.frame.height
            )
            window.setFrame(frame, display: true)
        } else {
            window.center()
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        inputView.window?.makeFirstResponder(inputView)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(visualEffect)

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 34, left: 12, bottom: 10, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(root)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            root.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            root.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.alignment = .centerY

        configureLanguagePopup(sourcePopup, selectedIndex: 1)
        configureLanguagePopup(targetPopup, selectedIndex: 0)
        configureButton(swapButton, action: #selector(swapLanguages))
        swapButton.bezelStyle = .circular
        swapButton.toolTip = "Поменять языки"

        toolbar.addArrangedSubview(sourcePopup)
        toolbar.addArrangedSubview(swapButton)
        toolbar.addArrangedSubview(targetPopup)
        toolbar.addArrangedSubview(NSView())

        root.addArrangedSubview(toolbar)
        root.addArrangedSubview(makeScrollView(for: inputView, placeholder: "Введите текст", height: 66))
        root.addArrangedSubview(makeScrollView(for: outputView, placeholder: "Перевод", height: 66))

        inputView.font = .systemFont(ofSize: 14, weight: .regular)
        inputView.delegate = self
        inputView.isAutomaticQuoteSubstitutionEnabled = false
        inputView.isAutomaticDashSubstitutionEnabled = false
        outputView.font = .systemFont(ofSize: 14, weight: .regular)
        outputView.isEditable = false
        outputView.textColor = .labelColor

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 10
        footer.alignment = .centerY
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)

        configureButton(translateButton, action: #selector(translateNow))
        translateButton.keyEquivalent = "\r"
        translateButton.bezelColor = NSColor.systemPink
        configureButton(copyButton, action: #selector(copyResult))

        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(copyButton)
        footer.addArrangedSubview(translateButton)
        root.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            sourcePopup.widthAnchor.constraint(equalToConstant: 116),
            targetPopup.widthAnchor.constraint(equalToConstant: 116),
            swapButton.widthAnchor.constraint(equalToConstant: 26),
            swapButton.heightAnchor.constraint(equalToConstant: 26),
            translateButton.widthAnchor.constraint(equalToConstant: 96),
            copyButton.widthAnchor.constraint(equalToConstant: 102)
        ])
    }

    private func configureLanguagePopup(_ popup: NSPopUpButton, selectedIndex: Int) {
        popup.addItems(withTitles: languages.map { "\($0.shortName)  \($0.name)" })
        popup.selectItem(at: selectedIndex)
        popup.controlSize = .regular
        popup.font = .systemFont(ofSize: 12, weight: .medium)
        popup.target = self
        popup.action = #selector(languageChanged)
    }

    private func configureButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.controlSize = .regular
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
    }

    private func makeScrollView(for textView: NSTextView, placeholder: String, height: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: height).isActive = true

        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 9, height: 8)
        textView.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        textView.layer?.cornerRadius = 10
        textView.string = ""
        textView.toolTip = placeholder

        scrollView.documentView = textView
        return scrollView
    }

    @objc private func languageChanged() {
        scheduleTranslation()
    }

    @objc private func swapLanguages() {
        let sourceIndex = sourcePopup.indexOfSelectedItem
        sourcePopup.selectItem(at: targetPopup.indexOfSelectedItem)
        targetPopup.selectItem(at: sourceIndex)

        let oldInput = inputView.string
        inputView.string = outputView.string
        outputView.string = oldInput
        scheduleTranslation()
    }

    @objc private func translateNow() {
        translateTask?.cancel()
        startTranslation()
    }

    @objc private func copyResult() {
        let result = outputView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        statusLabel.stringValue = "Скопировано"
    }

    private func scheduleTranslation() {
        guard settings.autoTranslate else { return }

        translateTask?.cancel()
        translateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.startTranslation()
            }
        }
    }

    private func startTranslation() {
        let text = inputView.string
        let source = languages[sourcePopup.indexOfSelectedItem]
        let target = languages[targetPopup.indexOfSelectedItem]
        let translator = self.translator

        translateTask?.cancel()
        translateTask = Task { [weak self] in
            await MainActor.run {
                self?.statusLabel.stringValue = "Перевожу..."
                self?.translateButton.isEnabled = false
            }

            do {
                let result = try await translator.translate(text, from: source, to: target)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.outputView.string = result
                    self?.statusLabel.stringValue = "Готово"
                    self?.translateButton.isEnabled = true
                }
            } catch TranslationService.TranslationError.emptyText {
                await MainActor.run {
                    self?.outputView.string = ""
                    self?.statusLabel.stringValue = "Введите текст"
                    self?.translateButton.isEnabled = true
                }
            } catch {
                await MainActor.run {
                    self?.outputView.string = ""
                    self?.statusLabel.stringValue = "Нет сети или сервис недоступен"
                    self?.translateButton.isEnabled = true
                }
            }
        }
    }
}

extension TranslatorWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        scheduleTranslation()
    }
}

@MainActor
private final class SettingsWindowController: NSWindowController {
    private let settings: AppSettings
    private let showOnLaunchButton = NSButton(checkboxWithTitle: "Показывать окно при запуске", target: nil, action: nil)
    private let autoHideButton = NSButton(checkboxWithTitle: "Скрывать при переходе в другое приложение", target: nil, action: nil)
    private let autoTranslateButton = NSButton(checkboxWithTitle: "Переводить автоматически", target: nil, action: nil)

    init(settings: AppSettings) {
        self.settings = settings

        let contentSize = NSSize(width: 390, height: 300)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.minSize = contentSize
        window.maxSize = contentSize

        super.init(window: window)
        buildInterface()
        syncState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(visualEffect)

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 40, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(root)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            root.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            root.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
        ])

        let header = makeHeader()
        let options = makeOptionsBox()
        let hotkey = makeInfoRow(title: "Горячая клавиша", value: "Command + Option + T")
        let service = makeInfoRow(title: "Сервис", value: "MyMemory + локальный словарь")

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let versionLabel = NSTextField(labelWithString: "LinguaBar 1.0")
        versionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .tertiaryLabelColor

        let quitButton = NSButton(title: "Выйти", target: self, action: #selector(quitApp))
        quitButton.bezelStyle = .rounded
        quitButton.controlSize = .regular
        quitButton.font = .systemFont(ofSize: 12, weight: .semibold)

        footer.addArrangedSubview(versionLabel)
        footer.addArrangedSubview(NSView())
        footer.addArrangedSubview(quitButton)

        root.addArrangedSubview(header)
        root.addArrangedSubview(options)
        root.addArrangedSubview(hotkey)
        root.addArrangedSubview(service)
        root.addArrangedSubview(NSView())
        root.addArrangedSubview(footer)
    }

    private func makeHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let logo = NSImageView(image: makeSettingsLogo())
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 34).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.spacing = 1

        let title = NSTextField(labelWithString: "LinguaBar")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: "быстрый переводчик в строке меню")
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        textStack.addArrangedSubview(title)
        textStack.addArrangedSubview(subtitle)

        row.addArrangedSubview(logo)
        row.addArrangedSubview(textStack)
        row.addArrangedSubview(NSView())
        return row
    }

    private func makeOptionsBox() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.wantsLayer = true
        stack.layer?.cornerRadius = 10
        stack.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor

        [showOnLaunchButton, autoHideButton, autoTranslateButton].forEach {
            $0.target = self
            $0.action = #selector(settingsChanged)
            $0.font = .systemFont(ofSize: 12, weight: .medium)
            stack.addArrangedSubview($0)
        }

        return stack
    }

    private func makeInfoRow(title: String, value: String) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        valueLabel.textColor = .labelColor

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(valueLabel)
        return row
    }

    private func syncState() {
        showOnLaunchButton.state = settings.showOnLaunch ? .on : .off
        autoHideButton.state = settings.autoHide ? .on : .off
        autoTranslateButton.state = settings.autoTranslate ? .on : .off
    }

    @objc private func settingsChanged() {
        settings.showOnLaunch = showOnLaunchButton.state == .on
        settings.autoHide = autoHideButton.state == .on
        settings.autoTranslate = autoTranslateButton.state == .on
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func makeSettingsLogo() -> NSImage {
        let image = NSImage(size: NSSize(width: 34, height: 34))
        image.lockFocus()

        let rect = NSRect(x: 1, y: 1, width: 32, height: 32)
        NSColor.systemPink.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()

        let bubble = NSBezierPath(roundedRect: NSRect(x: 8, y: 10, width: 18, height: 15), xRadius: 4, yRadius: 4)
        NSColor.white.setStroke()
        bubble.lineWidth = 2
        bubble.stroke()

        let letter = NSBezierPath()
        letter.move(to: NSPoint(x: 12, y: 13))
        letter.line(to: NSPoint(x: 17, y: 22))
        letter.line(to: NSPoint(x: 22, y: 13))
        letter.move(to: NSPoint(x: 14, y: 16.2))
        letter.line(to: NSPoint(x: 20, y: 16.2))
        NSColor.white.setStroke()
        letter.lineWidth = 2
        letter.lineCapStyle = .round
        letter.lineJoinStyle = .round
        letter.stroke()

        image.unlockFocus()
        return image
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + OSType(scalar.value)
    }
    return result
}

@main
private enum LinguaBarApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        app.delegate = appDelegate
        app.run()

        _ = appDelegate
    }
}
