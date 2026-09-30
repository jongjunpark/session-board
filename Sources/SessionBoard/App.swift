// 창·앱 수명 주기
import AppKit
import SwiftUI

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    // 이 앱은 활성화되지 않는 창이라, 창 전체 호버는 항상 켜진 추적 영역으로 직접 받는다
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onPress?()
        super.mouseDown(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}

final class BoardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = BoardModel()
    private var panel: BoardPanel?
    private var host: FirstMouseHostingView<AnchoredBoard>?
    // 내용의 원래 크기를 재는 용도 (화면에 붙지 않음)
    private var timer: Timer?
    private var fitGeneration = 0
    private var isResizing = false
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !demoMode {
            Installer.prepareOnLaunch()
            BoardConfig.shared.save() // 스크립트가 읽을 설정 파일을 늘 만들어 둔다
        }

        let panel = BoardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // 그림자는 유리 효과가 직접 그린다 (창 그림자는 여백까지 네모로 그려짐)
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let host = FirstMouseHostingView(rootView: AnchoredBoard(model: model))
        host.sizingOptions = [] // 창 크기는 transition 이 정한다 (제약이 애니메이션과 다투지 않게)
        panel.contentView = host
        host.onHoverChange = { [weak self] inside in self?.model.hoverChanged(inside) }
        host.onPress = { [weak self] in self?.model.holdPeek() }
        // 실제 포인터가 유리 판(창에서 여백을 뺀 곳) 위에 있는지
        model.pointerInside = { [weak panel] in
            guard let frame = panel?.frame else { return false }
            return frame.insetBy(dx: AnchoredBoard.margin, dy: AnchoredBoard.margin).contains(NSEvent.mouseLocation)
        }
        // 접기 버튼은 유리 판 오른쪽 위 (위쪽 줄 여백 12·9, 버튼 18) — 가장자리를 조금 넉넉히 잡는다
        model.pointerOnToggle = { [weak panel] in
            guard let frame = panel?.frame else { return false }
            let right = frame.maxX - AnchoredBoard.margin - 12
            let top = frame.maxY - AnchoredBoard.margin - 9
            let button = NSRect(x: right - 18, y: top - 18, width: 18, height: 18).insetBy(dx: -6, dy: -6)
            return button.contains(NSEvent.mouseLocation)
        }
        self.panel = panel
        self.host = host

        let size = contentSize(collapsed: model.collapsed, peek: false, items: model.items)
        // 데모는 저장된 위치를 쓰지 않고 화면 가운데쯤에 띄운다
        let topRight = demoMode ? demoTopRight() : (savedTopRight() ?? defaultTopRight())
        panel.setFrame(NSRect(x: topRight.x - size.width, y: topRight.y - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()

        // 오른쪽 위 모서리를 기억한다 (접고 펼 때 기준점)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak panel, weak self] _ in
            MainActor.assumeIsolated {
                guard let frame = panel?.frame else { return }
                if !demoMode { UserDefaults.standard.set([frame.maxX, frame.maxY], forKey: "topRight") }
                // 사용자가 끄는 중일 때만 (크기 맞추느라 창이 움직인 건 제외) 호버 목록을 막는다
                if self?.isResizing == false { self?.model.holdPeek() }
            }
        }

        model.onRequest = { [weak self] collapsed, peek, items in
            self?.transition(collapsed: collapsed, peek: peek, items: items)
        }
        if demoMode {
            model.request(collapsed: false, peek: false, items: DemoData.items)
            // 메뉴 막대도 예시 데이터로 (켜짐 설정은 저장하지 않는다)
            let menuBar = MenuBarController(model: model)
            menuBar.setEnabled(true, persist: false)
            self.menuBar = menuBar
            return
        }
        // 새 버전 표시가 생기거나 없어지면 창 크기를 다시 맞춘다
        Updater.shared.onAvailabilityChange = { [weak self] in self?.model.request() }
        Updater.shared.scheduleChecks()

        // 메뉴 막대 표시
        let menuBar = MenuBarController(model: model)
        menuBar.setEnabled(MenuBarController.enabled)
        MenuBarController.current = menuBar
        self.menuBar = menuBar

        // 플로팅 창 보기/숨기기 (메뉴 막대에서). 숨긴 상태는 기억한다
        if UserDefaults.standard.bool(forKey: "boardHidden") { panel.orderOut(nil) }
        NotificationCenter.default.addObserver(forName: .toggleBoardWindow, object: nil, queue: .main) { [weak panel] _ in
            MainActor.assumeIsolated {
                guard let panel else { return }
                let hide = panel.isVisible
                if hide { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
                UserDefaults.standard.set(hide, forKey: "boardHidden")
            }
        }
        model.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.refresh() }
        }
    }

    // 주어진 상태일 때 유리 판 여백까지 포함한 창 크기.
    // 매번 새 복제 모델·새 측정기로 잰다 (같은 측정기를 다시 쓰면 SwiftUI 가 한 박자 늦게 반영해 직전 크기가 나온다)
    private func contentSize(collapsed: Bool, peek: Bool, items: [BoardItem]) -> NSSize {
        let probe = BoardModel()
        probe.apply(collapsed: collapsed, peek: peek, items: items, animated: false, persist: false)
        let inner = NSHostingController(rootView: BoardView(model: probe))
            .sizeThatFits(in: NSSize(width: 2000, height: 2000))
        let margin = AnchoredBoard.margin * 2
        return NSSize(width: ceil(inner.width + margin), height: ceil(inner.height + margin))
    }

    // 오른쪽 위 모서리를 창 기준점으로 둔 채 크기만 바꾼다 (움직임 없음)
    private func resize(to size: NSSize) {
        guard let panel else { return }
        let current = panel.frame
        guard abs(current.width - size.width) > 0.5 || abs(current.height - size.height) > 0.5 else { return }
        isResizing = true
        panel.setFrame(NSRect(x: current.maxX - size.width, y: current.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        isResizing = false
    }

    // 상태 전환 순서:
    //  1) 새 크기를 미리 재서, 옛 크기와 새 크기가 모두 들어가게 창을 먼저 넓힌다 (움직임 없음.
    //     내용은 오른쪽 위에 붙어 있어서 화면상 제자리)
    //  2) 다음 틱에 유리 판만 부드럽게 늘리거나 줄인다
    //  3) 움직임이 끝나면 창을 새 크기에 딱 맞춘다
    private func transition(collapsed: Bool, peek: Bool, items: [BoardItem]) {
        guard let panel else { return }
        let target = contentSize(collapsed: collapsed, peek: peek, items: items)
        let current = panel.frame.size
        resize(to: NSSize(width: max(current.width, target.width), height: max(current.height, target.height)))

        fitGeneration += 1
        let generation = fitGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.fitGeneration else { return }
            self.model.apply(collapsed: collapsed, peek: peek, items: items)
            DispatchQueue.main.asyncAfter(deadline: .now() + BoardModel.motionDuration) { [weak self] in
                guard let self, generation == self.fitGeneration else { return }
                self.resize(to: target)
            }
        }
    }

    private func savedTopRight() -> NSPoint? {
        let defaults = UserDefaults.standard
        var point: NSPoint?
        if let saved = defaults.array(forKey: "topRight") as? [Double], saved.count == 2 {
            point = NSPoint(x: saved[0], y: saved[1])
        } else if let old = defaults.array(forKey: "topLeft") as? [Double], old.count == 2 {
            // 예전 버전은 왼쪽 위를 저장했다 — 펼친 폭(유리 여백 포함)으로 오른쪽 위를 추정
            point = NSPoint(x: old[0] + 320 + AnchoredBoard.margin * 2, y: old[1])
        }
        guard let point else { return nil }
        // 모니터 구성이 바뀌어 화면 밖이면 기본 위치로
        let visible = NSScreen.screens.contains { $0.frame.insetBy(dx: -20, dy: -20).contains(point) }
        return visible ? point : nil
    }

    private func demoTopRight() -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.midX + 200, y: screen.midY + 250)
    }

    private func defaultTopRight() -> NSPoint {
        let screen = NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: screen.maxX - 4, y: screen.maxY - 4)
    }
}

@main
enum SessionBoardMain {
    static func main() {
        // 창 없이 훅만 넣고 빼는 명령 (Homebrew 제거·시험용)
        //   SessionBoard --install-hooks | --uninstall-hooks
        let args = CommandLine.arguments
        if args.contains("--version") {
            print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
            exit(0)
        }
        // 창 없이 새 버전을 확인해 있으면 바로 업데이트하고 끝낸다
        if args.contains("--self-update") {
            Task { @MainActor in
                await Updater.shared.check(userInitiated: false)
                guard let release = Updater.shared.available else {
                    print("최신 버전이에요 (\(Updater.shared.currentVersion))")
                    exit(0)
                }
                print("\(Updater.shared.currentVersion) → \(release.version) 업데이트")
                await Updater.shared.install(release)
                exit(1) // install 이 끝내지 못했으면 실패
            }
            dispatchMain()
        }
        if args.contains("--install-hooks") || args.contains("--uninstall-hooks") {
            let ok = MainActor.assumeIsolated { () -> Bool in
                do {
                    if args.contains("--install-hooks") {
                        try Installer.syncLegacyScripts()
                        try Installer.installHooks(.claude)
                        if HookTarget.codexAvailable { try Installer.installHooks(.codex) }
                        try Installer.syncLegacyScripts()
                    } else {
                        try Installer.uninstallHooks(.claude)
                        try Installer.uninstallHooks(.codex)
                    }
                    return true
                } catch {
                    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                    return false
                }
            }
            exit(ok ? 0 : 1)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
