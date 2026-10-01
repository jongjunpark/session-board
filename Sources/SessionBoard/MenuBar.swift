// 메뉴 막대 표시 — 개수(● 확인 필요 · ⟳ 진행중 · ✓ 완료)와, 누르면 펼쳐지는 세션 목록
import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let enabledKey = "menuBarEnabled"
    static weak var current: MenuBarController? // 설정 창에서 켜고 끌 때 쓴다

    private let model: BoardModel
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    private static let needsColor = NSColor(red: 0.93, green: 0.62, blue: 0.10, alpha: 1)
    private static let doneColor = NSColor(red: 0.19, green: 0.64, blue: 0.42, alpha: 1)

    init(model: BoardModel) {
        self.model = model
        super.init()
        model.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
        Updater.shared.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateTitle() }
            .store(in: &cancellables)
    }

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func setEnabled(_ on: Bool, persist: Bool = true) {
        if persist { UserDefaults.standard.set(on, forKey: Self.enabledKey) }
        if on {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self // 열 때마다 최신 목록으로 다시 만든다
            item.menu = menu
            statusItem = item
            updateTitle()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: 제목 (개수)

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let parts: [(String, NSColor?)] = [
            model.needs.isEmpty ? nil : ("● \(model.needs.count)", Self.needsColor),
            model.running.isEmpty ? nil : ("⟳ \(model.running.count)", nil),
            model.done.isEmpty ? nil : ("✓ \(model.done.count)", Self.doneColor),
            Updater.shared.available == nil ? nil : ("↑", nil),
        ].compactMap { $0 }

        if parts.isEmpty {
            button.attributedTitle = NSAttributedString()
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "SessionBoard")
            return
        }
        button.image = nil
        let title = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        for (index, part) in parts.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: "  ", attributes: [.font: font])) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let color = part.1 { attributes[.foregroundColor] = color }
            title.append(NSAttributedString(string: part.0, attributes: attributes))
        }
        button.attributedTitle = title
    }

    // MARK: 목록

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        section(menu, "확인 필요", model.needs)
        section(menu, "진행중", model.running)
        section(menu, "완료", model.done)
        if model.items.isEmpty {
            menu.addItem(disabled("실행 중인 세션이 없어요"))
        }
        menu.addItem(.separator())
        if !model.done.isEmpty {
            menu.addItem(action("완료 전부 확인") { [weak self] in self?.model.checkAllDone() })
        }
        if let release = Updater.shared.available {
            menu.addItem(action("새 버전 \(release.version)으로 업데이트…") { Updater.shared.confirmInstall(release) })
        }
        menu.addItem(action("플로팅 창 보기/숨기기") { NotificationCenter.default.post(name: .toggleBoardWindow, object: nil) })
        menu.addItem(action("설정…") { SettingsWindow.show() })
        menu.addItem(action("종료") { NSApp.terminate(nil) })
    }

    private func section(_ menu: NSMenu, _ title: String, _ items: [BoardItem]) {
        guard !items.isEmpty else { return }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(disabled("\(title) \(items.count)"))
        for item in items {
            let row = action("\(item.agent == "codex" ? ">_" : "✳")  \(item.title)  ·  \(item.label)") { [weak self] in self?.model.open(item) }
            if item.state == "needs_input" {
                row.attributedTitle = NSAttributedString(
                    string: row.title, attributes: [.foregroundColor: Self.needsColor]
                )
            }
            let sub = NSMenu()
            if !item.summary.isEmpty { sub.addItem(disabled(item.summary)) }
            sub.addItem(action("세션 열기") { [weak self] in self?.model.open(item) })
            if item.bg_warn {
                let wait = BoardConfig.label(BoardConfig.shared.bgWarnMinutes)
                sub.addItem(action("기다리기 (\(wait) 뒤 다시 알림)") { [weak self] in self?.model.snooze(item) })
            }
            sub.addItem(action(item.state == "done" ? "확인 완료" : "목록에서 제거") { [weak self] in
                self?.model.check(item)
            })
            row.submenu = sub
            menu.addItem(row)
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        return item
    }
}

// 누르면 클로저를 부르는 메뉴 항목
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func fire() { handler() }
}

extension Notification.Name {
    static let toggleBoardWindow = Notification.Name("SessionBoardToggleWindow")
}
