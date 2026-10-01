// 세션 데이터 모델 — 데이터는 앱 안의 scripts/board-json.sh 가 만든다
import AppKit
import SwiftUI

struct BoardItem: Decodable, Identifiable, Equatable {
    let session_id: String
    let kind: String // app | terminal
    let local_id: String
    let app_bundle: String
    let title: String
    let state: String
    let reason: String
    let summary: String
    let stale: Bool
    let label: String
    let short: String // 짧은 목록용 (예: "12분", "5분 전", "확인 필요")
    let bg_count: Int // 아직 안 끝난 백그라운드 작업 수
    let bg_warn: Bool // 백그라운드 작업이 너무 오래 돌아 확인 필요로 올라온 항목
    let agent: String? // claude | codex
    var id: String { session_id }
}

@MainActor
final class BoardModel: ObservableObject {
    // 화면에 보이는 상태. 바꿀 때는 request(...) 로 요청하고, 창 크기를 먼저 맞춘 뒤 apply(...) 로 반영된다.
    @Published private(set) var items: [BoardItem] = []
    @Published private(set) var collapsed: Bool = UserDefaults.standard.bool(forKey: "collapsed")
    // 접힌 상태에서 마우스를 올려 두면 짧은 목록을 잠깐 펼친다
    @Published private(set) var peek = false
    // 펼친 창의 너비. 유리 판 왼쪽·오른쪽 가장자리를 끌어 바꾸고, 다음에 펼칠 때도 그대로 쓴다
    @Published var expandedWidth: CGFloat = BoardModel.savedWidth()
    static let minWidth: CGFloat = 320

    private static func savedWidth() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: "expandedWidth")
        return saved >= minWidth ? saved : minWidth
    }

    func saveWidth() {
        if !demoMode { UserDefaults.standard.set(Double(expandedWidth), forKey: "expandedWidth") }
    }

    // 펼침·접힘·목록 변화 공용 움직임: 넘치지 않고 끝에서 부드럽게 멈추는 감속 곡선
    static let motion = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)
    static let motionDuration: TimeInterval = 0.32

    // 창을 맡은 쪽(AppDelegate)이 받아서 창 크기를 먼저 맞추고 apply 를 부른다
    var onRequest: ((_ collapsed: Bool, _ peek: Bool, _ items: [BoardItem]) -> Void)?
    private var loading = false
    private var hoverWork: DispatchWorkItem?

    // 요청해 둔 목표 상태 (화면 반영은 한 틱 늦으므로, 다음 요청은 화면 값이 아니라 이 값을 기준으로 만든다)
    private lazy var wantCollapsed = collapsed
    private var wantPeek = false
    private var wantItems: [BoardItem]?

    func request(collapsed: Bool? = nil, peek: Bool? = nil, items: [BoardItem]? = nil) {
        let nextCollapsed = collapsed ?? wantCollapsed
        // 큰 화면에서는 짧은 목록을 쓰지 않는다
        let nextPeek = nextCollapsed ? (peek ?? wantPeek) : false
        let nextItems = items ?? wantItems ?? self.items
        wantCollapsed = nextCollapsed
        wantPeek = nextPeek
        wantItems = nextItems
        onRequest?(nextCollapsed, nextPeek, nextItems)
    }

    // 애니메이션과 함께 화면 상태를 바꾼다 (창 크기는 이미 넉넉히 맞춰진 상태)
    func apply(collapsed: Bool, peek: Bool, items: [BoardItem], animated: Bool = true, persist: Bool = true) {
        if persist, !demoMode, collapsed != self.collapsed { UserDefaults.standard.set(collapsed, forKey: "collapsed") }
        let change = {
            self.collapsed = collapsed
            self.peek = peek
            self.items = items
        }
        if animated { withAnimation(BoardModel.motion, change) } else { change() }
    }

    // 접기를 누르거나 창을 끈 뒤에는, 포인터가 정말 창 밖으로 나갈 때까지 호버 목록을 열지 않는다.
    // 창 크기가 바뀔 때 시스템이 들어옴/나감 신호를 잘못 보내기도 해서, 신호 대신 실제 포인터 위치로 푼다.
    private var holdPeekUntilExit = false
    private var holdWatch: Timer?
    var pointerInside: (() -> Bool)? // 창을 맡은 쪽이 채운다

    var pointerOnToggle: (() -> Bool)? // 포인터가 접기 버튼 위에 있는지

    enum HoldArea { case window, toggle }

    // window: 창을 끌 때 — 창 밖으로 나가야 풀림
    // toggle: 접기를 누른 뒤 — 버튼에서만 벗어나면 풀리고, 몸통 위에 있으면 바로 호버 목록을 연다
    func holdPeek(_ area: HoldArea = .window) {
        hoverWork?.cancel()
        holdPeekUntilExit = true
        holdWatch?.invalidate()
        holdWatch = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let stillHeld = area == .toggle
                    ? (self.pointerOnToggle?() ?? false)
                    : (self.pointerInside?() ?? false)
                guard !stillHeld else { return }
                self.holdPeekUntilExit = false
                timer.invalidate()
                // 버튼에서 몸통으로 옮겨 간 경우엔 창 안이라 들어옴 신호가 다시 오지 않으므로 직접 호버로 친다
                if self.pointerInside?() ?? false { self.hoverChanged(true) }
            }
        }
    }

    func toggleCollapsed() {
        hoverWork?.cancel()
        if !wantCollapsed { holdPeek(.toggle) }
        request(collapsed: !wantCollapsed, peek: false)
    }

    // 스치기만 해서는 펼치지 않도록 0.3초 머물러야 펼치고, 벗어나면 0.5초 뒤 접는다
    func hoverChanged(_ inside: Bool) {
        hoverWork?.cancel()
        guard wantCollapsed, !(inside && holdPeekUntilExit) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantCollapsed, self.wantPeek != inside else { return }
            self.request(peek: inside)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.3 : 0.5), execute: work)
    }

    var needs: [BoardItem] { items.filter { $0.state == "needs_input" } }
    var running: [BoardItem] { items.filter { $0.state == "running" } }
    var done: [BoardItem] { items.filter { $0.state == "done" } }

    func refresh() {
        guard !demoMode, !loading else { return }
        loading = true
        Task.detached {
            let next = BoardModel.load()
            await MainActor.run {
                self.loading = false
                guard let next, next != self.items else { return }
                self.request(items: next)
            }
        }
    }

    nonisolated private static func load() -> [BoardItem]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptsDir + "/board-json.sh"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return try? JSONDecoder().decode([BoardItem].self, from: data)
    }

    func open(_ item: BoardItem) {
        // 터미널에서 띄운 Codex CLI 세션은 그 터미널 앱을 앞으로 (Claude 터미널 세션과 같게)
        let codexTerminal = item.kind == "codex" && !item.app_bundle.isEmpty && item.app_bundle != "com.openai.codex"
        if item.kind == "codex" && !codexTerminal {
            // Codex 앱에서 그 스레드를 연다
            if let url = URL(string: "codex://threads/\(item.local_id)") { NSWorkspace.shared.open(url) }
            return
        }
        if item.kind == "terminal" || codexTerminal {
            // 터미널 세션은 특정 탭으로 들어갈 수 없어서, 띄운 앱(iTerm 등)을 앞으로 가져온다
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.app_bundle) else { return }
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        guard let url = URL(string: "claude://claude.ai/epitaxy/\(item.local_id)") else { return }
        NSWorkspace.shared.open(url)
    }

    // 세션 번호는 파일 이름이 되므로 영문·숫자·- 만 받는다 (../ 로 기록 폴더 밖의 파일을 지우지 못하게)
    nonisolated static func stateFile(_ sessionID: String) -> String? {
        guard !sessionID.isEmpty,
              sessionID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" }),
              sessionID.allSatisfy(\.isASCII) else { return nil }
        return "\(boardDir)/state/\(sessionID).json"
    }

    func check(_ item: BoardItem) {
        if let path = BoardModel.stateFile(item.session_id) { try? FileManager.default.removeItem(atPath: path) }
        refresh()
    }

    func checkAllDone() {
        for item in done {
            if let path = BoardModel.stateFile(item.session_id) { try? FileManager.default.removeItem(atPath: path) }
        }
        refresh()
    }

    // 오래 걸리는 백그라운드 작업 알림을 한 번 더 미룬다 (정상으로 도는 걸 확인했을 때)
    func snooze(_ item: BoardItem) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptsDir + "/action.sh", "snooze", item.session_id]
        process.terminationHandler = { _ in
            Task { @MainActor in self.refresh() }
        }
        try? process.run()
    }
}
