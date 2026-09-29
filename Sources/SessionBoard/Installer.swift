// 설치·제거 — 훅 스크립트 배치, Claude Code(~/.claude/settings.json)·Codex(~/.codex/hooks.json)에 훅 등록, 로그인 시 실행
import AppKit
import ServiceManagement

// 시험할 때 SESSION_BOARD_HOME 으로 홈 폴더를 바꿀 수 있다 (실제 설정을 건드리지 않게)
let homeDir = ProcessInfo.processInfo.environment["SESSION_BOARD_HOME"] ?? NSHomeDirectory()
let boardDir = homeDir + "/.claude/session-board"

// 훅을 넣을 곳: Claude Code 와 Codex 는 설정 파일 위치·명령·이벤트만 다르고 형식은 같다
struct HookTarget: Equatable {
    let name: String
    let settingsPath: String
    let command: String
    let specs: [(event: String, matcher: String?)] // matcher 가 nil 이면 넣지 않는다 (모든 경우)

    static func == (lhs: HookTarget, rhs: HookTarget) -> Bool { lhs.settingsPath == rhs.settingsPath }

    static let claude = HookTarget(
        name: "Claude Code",
        settingsPath: homeDir + "/.claude/settings.json",
        command: boardDir + "/bin/hook.sh",
        specs: [
            ("UserPromptSubmit", ""),
            ("PreToolUse", "AskUserQuestion|ExitPlanMode"),
            ("PermissionRequest", ""),
            ("Notification", "permission_prompt|elicitation_dialog"),
            ("PostToolUse", ""),
            ("PostToolUseFailure", ""),
            ("PermissionDenied", ""),
            ("Stop", ""),
            ("StopFailure", ""),
        ]
    )

    static let codex = HookTarget(
        name: "Codex",
        settingsPath: homeDir + "/.codex/hooks.json",
        command: boardDir + "/bin/hook.sh --agent codex",
        specs: [
            ("UserPromptSubmit", nil),
            ("PreToolUse", "request_user_input"),
            ("PermissionRequest", nil),
            ("PostToolUse", nil),
            ("Stop", nil),
            ("Interrupt", nil),
        ]
    )

    // Codex 를 쓰는 맥에서만 Codex 연동을 보여 준다
    static var codexAvailable: Bool {
        FileManager.default.fileExists(atPath: homeDir + "/.codex")
    }
}

@MainActor
enum Installer {
    static let binDir = boardDir + "/bin"
    static let hookCommand = binDir + "/hook.sh"

    enum InstallError: LocalizedError {
        case unreadableSettings(String, String)

        var errorDescription: String? {
            switch self {
            case .unreadableSettings(let path, let detail):
                return "\(path.replacingOccurrences(of: homeDir, with: "~")) 을 읽을 수 없어요. 파일을 고치지 않았어요.\n\(detail)"
            }
        }
    }

    // MARK: 스크립트

    // 앱에 들어 있는 스크립트를 ~/.claude/session-board/bin 에 깐다. 앱을 업데이트하면 실행할 때마다 새 버전으로 바뀐다.
    static func installScripts() throws {
        guard let source = Bundle.main.resourceURL?.appendingPathComponent("scripts") else { return }
        let fm = FileManager.default
        try fm.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: boardDir + "/state", withIntermediateDirectories: true)
        for name in try fm.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".sh") {
            let target = binDir + "/" + name
            if fm.fileExists(atPath: target) { try fm.removeItem(atPath: target) }
            try fm.copyItem(atPath: source.appendingPathComponent(name).path, toPath: target)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target)
        }
    }

    // macOS 15 부터 /usr/bin/jq 가 기본으로 들어 있다. 그 전 버전은 Homebrew jq 가 필요하다.
    static var hasJQ: Bool {
        ["/usr/bin/jq", "/opt/homebrew/bin/jq", "/usr/local/bin/jq"].contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    // MARK: 훅 (Claude Code · Codex 공용)

    private static func loadSettings(_ target: HookTarget) throws -> [String: Any] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: target.settingsPath) else { return [:] }
        let data = try Data(contentsOf: URL(fileURLWithPath: target.settingsPath))
        if data.isEmpty { return [:] }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallError.unreadableSettings(target.settingsPath, "최상위가 JSON 객체가 아니에요.")
            }
            return object
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.unreadableSettings(target.settingsPath, error.localizedDescription)
        }
    }

    private static func saveSettings(_ settings: [String: Any], _ target: HookTarget) throws {
        let fm = FileManager.default
        let path = target.settingsPath
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        // 고치기 전 원본을 남긴다
        if fm.fileExists(atPath: path) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let base = path + ".bak-session-board-" + formatter.string(from: Date())
            var backup = base
            var n = 1
            while fm.fileExists(atPath: backup) { n += 1; backup = base + "-\(n)" } // 같은 초에 두 번 고쳐도 겹치지 않게
            try fm.copyItem(atPath: path, toPath: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private static func groupHasOurHook(_ group: Any, _ target: HookTarget) -> Bool {
        guard let hooks = (group as? [String: Any])?["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String) == target.command }
    }

    static func hooksInstalled(_ target: HookTarget = .claude) -> Bool {
        guard let settings = try? loadSettings(target), let hooks = settings["hooks"] as? [String: Any] else { return false }
        return target.specs.allSatisfy { spec in
            ((hooks[spec.event] as? [Any]) ?? []).contains { groupHasOurHook($0, target) }
        }
    }

    // 이미 있는 다른 훅은 그대로 두고, 빠진 것만 더한다
    static func installHooks(_ target: HookTarget = .claude) throws {
        var settings = try loadSettings(target)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for spec in target.specs {
            var groups = hooks[spec.event] as? [Any] ?? []
            if groups.contains(where: { groupHasOurHook($0, target) }) { continue }
            var group: [String: Any] = ["hooks": [["type": "command", "command": target.command, "timeout": 5]]]
            if let matcher = spec.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[spec.event] = groups
            changed = true
        }
        guard changed else { return }
        settings["hooks"] = hooks
        try saveSettings(settings, target)
    }

    // 세션 보드 훅만 뺀다
    static func uninstallHooks(_ target: HookTarget = .claude) throws {
        var settings = try loadSettings(target)
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept = groups.filter { !groupHasOurHook($0, target) }
            guard kept.count != groups.count else { continue }
            changed = true
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        guard changed else { return }
        if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        try saveSettings(settings, target)
    }

    // MARK: 로그인 시 실행

    static var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            alert("로그인 시 실행 설정을 바꾸지 못했어요", error.localizedDescription)
        }
    }

    // MARK: 첫 실행

    // 스크립트는 늘 최신으로 깔고, 훅이 없으면 한 번 물어본다
    static func prepareOnLaunch() {
        if !hasJQ {
            alert("jq 가 필요해요", "macOS 15 이상에는 기본으로 들어 있어요. 그 전 버전이면 터미널에서 `brew install jq` 로 설치한 뒤 다시 열어 주세요.")
        }
        do {
            try installScripts()
        } catch {
            alert("스크립트를 설치하지 못했어요", error.localizedDescription)
            return
        }
        // 처음 실행할 때 한 번만 로그인 시 실행을 켠다 (그 뒤로는 사용자가 메뉴에서 정한 대로)
        if !UserDefaults.standard.bool(forKey: "firstLaunchDone") {
            UserDefaults.standard.set(true, forKey: "firstLaunchDone")
            if !launchAtLogin { setLaunchAtLogin(true) }
        }
        guard !missingTargets.isEmpty, !UserDefaults.standard.bool(forKey: "hooksDeclined") else { return }
        askToInstallHooks()
    }

    // 이 맥에서 연결할 수 있는데 아직 연결 안 된 도구 (Codex 는 쓰는 맥에서만)
    static var missingTargets: [HookTarget] {
        ([HookTarget.claude] + (HookTarget.codexAvailable ? [HookTarget.codex] : [])).filter { !hooksInstalled($0) }
    }

    static func askToInstallHooks() {
        let targets = missingTargets
        guard !targets.isEmpty else { return }
        let names = targets.map(\.name).joined(separator: "·")
        let files = targets.map { $0.settingsPath.replacingOccurrences(of: homeDir, with: "~") }.joined(separator: ", ")
        let alert = NSAlert()
        alert.messageText = "\(names)와 연결할까요?"
        var info = """
        세션이 시작·대기·완료될 때마다 상태를 기록하려면 훅이 필요해요. (\(files))
        이미 있는 다른 설정은 그대로 두고, 고치기 전 원본을 같은 폴더에 백업해 둬요.
        이미 돌고 있는 세션은 다음 요청부터 잡혀요.
        """
        if targets.contains(.codex) {
            info += "\n\nCodex 는 새 훅을 직접 허용해야 실행해요. 다음에 Codex 를 열 때 훅을 검토하라는 창이 뜨면 허용해 주세요. (CLI 에서는 \"Trust all and continue\")"
        }
        alert.informativeText = info
        alert.addButton(withTitle: "연결")
        alert.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            for target in targets {
                do {
                    try installHooks(target)
                } catch {
                    Installer.alert("\(target.name)와 연결하지 못했어요", error.localizedDescription)
                }
            }
            UserDefaults.standard.set(false, forKey: "hooksDeclined")
        } else {
            UserDefaults.standard.set(true, forKey: "hooksDeclined")
        }
    }

    // 훅·로그인 항목·기록을 모두 걷어내고 앱을 끝낸다 (앱 파일은 사용자가 휴지통으로)
    static func uninstallEverything() {
        let alert = NSAlert()
        alert.messageText = "SessionBoard를 삭제할까요?"
        alert.informativeText = "Claude Code·Codex 연결을 해제하고, 로그인 시 자동 실행을 끄고, ~/.claude/session-board 를 지운 뒤 앱을 종료해요. 앱 파일은 직접 휴지통으로 옮겨 주세요."
        alert.addButton(withTitle: "삭제")
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try uninstallHooks(.claude)
            try uninstallHooks(.codex)
        } catch {
            Installer.alert("연결을 해제하지 못했어요", error.localizedDescription)
            return
        }
        if launchAtLogin { setLaunchAtLogin(false) }
        try? FileManager.default.removeItem(atPath: boardDir)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        NSApp.terminate(nil)
    }

    static func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
