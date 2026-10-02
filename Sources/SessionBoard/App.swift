// 창·앱 수명 주기
import AppKit
import SwiftUI

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    // 이 앱은 활성화되지 않는 창이라, 창 전체 호버는 항상 켜진 추적 영역으로 직접 받는다
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 위에 얹은 가장자리 손잡이. SwiftUI 가 클릭을 먼저 가져가지 않게 손잡이부터 맞춰 본다
    var edgeHandles: [NSView] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        for handle in edgeHandles where !handle.isHidden {
            if handle.frame.contains(convert(point, from: superview)) { return handle }
        }
        return super.hitTest(point)
    }

    // 커서도 이 화면이 한곳에서 정한다. SwiftUI 는 포인터가 들어올 때 커서를 화살표로 정하는데,
    // 그게 손잡이보다 늦게 돌면 손잡이 커서를 덮는다 (바깥에서 들어올 때만 안 바뀌던 원인).
    // 그래서 SwiftUI 에 넘기기 전에 포인터가 손잡이 위인지 먼저 본다
    private var cursorOnHandle = false

    private func pointerOnHandle(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        return edgeHandles.contains { !$0.isHidden && $0.frame.contains(point) }
    }

    private func updateHandleCursor(_ event: NSEvent) -> Bool {
        if pointerOnHandle(event) {
            NSCursor.resizeLeftRight.set()
            cursorOnHandle = true
            // 같은 신호 처리 중에 SwiftUI 가 다시 화살표로 바꿔도 바로 되돌린다
            DispatchQueue.main.async { [weak self] in
                if self?.cursorOnHandle == true { NSCursor.resizeLeftRight.set() }
            }
            return true
        }
        if cursorOnHandle {
            cursorOnHandle = false
            NSCursor.arrow.set()
        }
        return false
    }

    override func cursorUpdate(with event: NSEvent) {
        if !updateHandleCursor(event) { super.cursorUpdate(with: event) }
    }

    override func mouseMoved(with event: NSEvent) {
        if !updateHandleCursor(event) { super.mouseMoved(with: event) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
        _ = updateHandleCursor(event)
    }

    var onPress: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onPress?()
        super.mouseDown(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
        if cursorOnHandle { cursorOnHandle = false; NSCursor.arrow.set() }
    }
}

// 펼친 유리 판의 왼쪽·오른쪽 가장자리. 끌면 너비가 바뀐다 (창 끌기로 넘어가지 않게 직접 받는다)
final class EdgeResizeHandle: NSView {
    enum Edge { case left, right }
    enum Phase { case began, changed, ended }

    let edge: Edge
    var onDrag: ((_ edge: Edge, _ phase: Phase, _ mouseX: CGFloat) -> Void)?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 활성화되지 않는 창이라 커서 영역 대신 항상 켜진 추적 영역으로 커서를 바꾼다.
    // 아래 SwiftUI 화면이 커서를 화살표로 되돌리므로, 들어올 때 한 번이 아니라 움직일 때마다 다시 정한다
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    private var dragging = false
    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }
    override func mouseDown(with event: NSEvent) {
        dragging = true
        NSCursor.resizeLeftRight.set()
        onDrag?(edge, .began, NSEvent.mouseLocation.x)
    }
    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set() // 끄는 동안 포인터가 손잡이를 벗어나도 유지
        onDrag?(edge, .changed, NSEvent.mouseLocation.x)
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        onDrag?(edge, .ended, NSEvent.mouseLocation.x)
        if !NSPointInRect(convert(event.locationInWindow, from: nil), bounds) { NSCursor.arrow.set() }
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
    private let leftHandle = EdgeResizeHandle(edge: .left)
    private let rightHandle = EdgeResizeHandle(edge: .right)
    // 너비를 끌기 시작할 때의 포인터 위치·너비·창 위치
    private var widthDrag: (mouseX: CGFloat, width: CGFloat, frame: NSRect)?

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
        panel.acceptsMouseMovedEvents = true // 가장자리 손잡이가 움직임마다 커서를 다시 정한다

        let host = FirstMouseHostingView(rootView: AnchoredBoard(model: model))
        host.sizingOptions = [] // 창 크기는 transition 이 정한다 (제약이 애니메이션과 다투지 않게)
        // SwiftUI 화면을 창에 바로 둔다. 다른 뷰로 감싸면 유리 효과가 창 전체에 바탕·그림자를 그린다
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
        for handle in [leftHandle, rightHandle] {
            handle.onDrag = { [weak self] edge, phase, x in self?.dragWidth(edge: edge, phase: phase, mouseX: x) }
            host.addSubview(handle)
            host.edgeHandles.append(handle)
        }

        let size = contentSize(collapsed: model.collapsed, peek: false, items: model.items)
        // 데모는 저장된 위치를 쓰지 않고 화면 가운데쯤에 띄운다
        let topRight = demoMode ? demoTopRight() : (savedTopRight() ?? defaultTopRight())
        panel.setFrame(NSRect(x: topRight.x - size.width, y: topRight.y - size.height,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        layoutHandles(collapsed: model.collapsed)

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
    private func contentSize(collapsed: Bool, peek: Bool, items: [BoardItem], width: CGFloat? = nil) -> NSSize {
        let probe = BoardModel()
        probe.expandedWidth = width ?? model.expandedWidth
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
                self.layoutHandles(collapsed: collapsed)
            }
        }
    }

    // 가장자리 손잡이를 유리 판의 왼쪽·오른쪽 끝에 둔다 (펼쳤을 때만)
    private func layoutHandles(collapsed: Bool) {
        guard let bounds = panel?.contentView?.bounds else { return }
        let margin = AnchoredBoard.margin
        // 유리 판 바깥 여백은 투명이라 마우스 신호가 아래 창으로 지나간다 (칠하면 창 전체에 회색 바탕이 생긴다).
        // 그래서 잡는 영역은 유리 판 안쪽으로 넓게 둔다
        let outside: CGFloat = 0, inside: CGFloat = 10
        let height = max(0, bounds.height - margin * 2)
        let right = bounds.width - margin
        let left = right - model.expandedWidth
        leftHandle.frame = NSRect(x: left - outside, y: margin, width: outside + inside, height: height)
        rightHandle.frame = NSRect(x: right - inside, y: margin, width: outside + inside, height: height)
        leftHandle.isHidden = collapsed
        rightHandle.isHidden = collapsed
    }

    // 왼쪽을 끌면 오른쪽 위 모서리를 그대로 두고 왼쪽으로 넓어진다.
    // 오른쪽을 끌면 오른쪽 끝이 따라 움직인다 (기준점도 함께 옮겨져 접힌 알약이 새 오른쪽 끝에 붙는다)
    private func dragWidth(edge: EdgeResizeHandle.Edge, phase: EdgeResizeHandle.Phase, mouseX: CGFloat) {
        guard let panel else { return }
        switch phase {
        case .began:
            widthDrag = (mouseX, model.expandedWidth, panel.frame)
        case .changed:
            guard let start = widthDrag else { return }
            let delta = edge == .left ? start.mouseX - mouseX : mouseX - start.mouseX
            let screenWidth = (panel.screen ?? NSScreen.main)?.visibleFrame.width ?? 1440
            let maxWidth = max(BoardModel.minWidth, (screenWidth / 2).rounded())
            let width = min(max((start.width + delta).rounded(), BoardModel.minWidth), maxWidth)
            guard width != model.expandedWidth else { return }
            let size = contentSize(collapsed: false, peek: false, items: model.items, width: width)
            let maxX = edge == .left ? start.frame.maxX : start.frame.maxX + (width - start.width)
            fitGeneration += 1 // 진행 중인 크기 맞추기가 끌기를 덮어쓰지 않게
            isResizing = true
            panel.setFrame(NSRect(x: maxX - size.width, y: start.frame.maxY - size.height,
                                  width: size.width, height: size.height), display: false)
            isResizing = false
            model.expandedWidth = width
            layoutHandles(collapsed: false)
        case .ended:
            widthDrag = nil
            model.saveWidth()
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
