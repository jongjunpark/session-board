// 업데이트 — GitHub 최신 릴리스를 확인하고, 설치 방식(zip / Homebrew)에 맞게 새 버전으로 바꾼다
import AppKit
import CryptoKit
import Foundation

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let zipURL: URL
        let sha256: String? // GitHub 가 알려 주는 파일 지문 (없으면 확인 생략)
        let pageURL: URL
    }

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published var notifyEnabled: Bool = UserDefaults.standard.object(forKey: "updateNotify") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(notifyEnabled, forKey: "updateNotify")
            scheduleChecks()
        }
    }

    // 새 버전 표시가 생기고 없어질 때 떠 있는 창 크기를 다시 맞추도록 알린다
    var onAvailabilityChange: (() -> Void)?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    // 설정 창의 GitHub 링크 (Info.plist 의 SBRepository, 예: jongjunpark/session-board)
    nonisolated static var repositoryURL: URL? {
        guard let repo = Bundle.main.object(forInfoDictionaryKey: "SBRepository") as? String, !repo.isEmpty else { return nil }
        return URL(string: "https://github.com/\(repo)")
    }
    private let repository = Bundle.main.object(forInfoDictionaryKey: "SBRepository") as? String ?? ""
    private var timer: Timer?

    var available: Release? {
        if case .available(let release) = status { return release }
        return nil
    }

    // Homebrew 로 설치했으면 앱이 직접 파일을 바꾸지 않고 brew upgrade 로 맡긴다 (Homebrew 가 아는 버전과 어긋나지 않게)
    var installedWithHomebrew: Bool {
        let caskroom = ["/opt/homebrew/Caskroom/session-board", "/usr/local/Caskroom/session-board"].contains {
            FileManager.default.fileExists(atPath: $0)
        }
        // 같은 맥에 Homebrew 설치본이 있어도, 지금 켜진 앱이 다른 곳에 있으면 그 앱을 직접 바꾼다
        return caskroom && Bundle.main.bundlePath == "/Applications/SessionBoard.app"
    }

    private var brewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: 확인

    // 켜져 있으면 앱을 켤 때(조금 뒤)와 6시간마다 확인한다
    func scheduleChecks() {
        timer?.invalidate()
        timer = nil
        guard notifyEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { await self?.check(userInitiated: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(userInitiated: false) }
        }
    }

    func check(userInitiated: Bool) async {
        guard !repository.isEmpty, status != .checking, status != .installing else { return }
        let wasAvailable = available != nil
        status = .checking
        do {
            let release = try await fetchLatest()
            if Self.isNewer(release.version, than: currentVersion) {
                status = .available(release)
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed("업데이트를 확인하지 못했어요: \(error.localizedDescription)")
        }
        if wasAvailable != (available != nil) { onAvailabilityChange?() }
        guard userInitiated else { return }
        switch status {
        case .upToDate:
            Installer.alert("최신 버전이에요", "지금 쓰는 \(currentVersion) 이 최신이에요.")
        case .available(let release):
            confirmInstall(release)
        case .failed(let message):
            Installer.alert("업데이트 확인 실패", message)
        default:
            break
        }
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData // 저장해 둔 옛 응답을 다시 쓰면 새 버전을 못 본다
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?
        }
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let zip = payload.assets.first(where: { $0.name == "SessionBoard.zip" }) else {
            throw URLError(.fileDoesNotExist)
        }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        let sha = zip.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        return Release(version: version, zipURL: zip.browser_download_url, sha256: sha, pageURL: payload.html_url)
    }

    // "0.10.0" > "0.9.3" 처럼 숫자 단위로 비교한다
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: 설치

    func confirmInstall(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "새 버전 \(release.version) 이 있어요"
        alert.informativeText = installedWithHomebrew
            ? "Homebrew 로 업데이트한 뒤 다시 켤게요. (지금 버전 \(currentVersion))"
            : "새 버전을 받아 바꾼 뒤 다시 켤게요. (지금 버전 \(currentVersion))"
        alert.addButton(withTitle: "지금 업데이트")
        alert.addButton(withTitle: "나중에")
        alert.addButton(withTitle: "변경 사항 보기")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await install(release) }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    func install(_ release: Release) async {
        status = .installing
        do {
            if installedWithHomebrew, let brew = brewPath {
                // 탭 목록을 먼저 새로 받아야 새 버전이 보인다 (HOMEBREW_NO_AUTO_UPDATE 가 켜져 있어도)
                try launchHelper("""
                env -u HOMEBREW_NO_AUTO_UPDATE "\(brew)" update --quiet
                "\(brew)" upgrade --cask session-board
                """)
            } else {
                let newApp = try await download(release)
                let target = Bundle.main.bundlePath
                try launchHelper("""
                rm -rf "\(target)"
                /bin/mv "\(newApp)" "\(target)"
                /usr/bin/xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
                """)
            }
            // 창 없이 돌 때(--self-update)는 앱 루프가 없으니 바로 끝낸다
            if NSApp?.isRunning == true { NSApp.terminate(nil) } else { exit(0) }
        } catch {
            status = .failed("업데이트하지 못했어요: \(error.localizedDescription)")
            Installer.alert("업데이트 실패", error.localizedDescription)
        }
    }

    // zip 을 받아 지문을 확인하고 풀어서, 새 앱 경로를 돌려준다
    private func download(_ release: Release) async throws -> String {
        let (tempZip, response) = try await URLSession.shared.download(from: release.zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let data = try Data(contentsOf: tempZip)
        if let expected = release.sha256 {
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else {
                throw NSError(domain: "SessionBoard", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "받은 파일의 지문이 릴리스와 달라요. 설치하지 않았어요."])
            }
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SessionBoard-update-\(release.version)")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", tempZip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = work.appendingPathComponent("SessionBoard.app")
        // 다른 앱이 섞여 들어오지 않았는지 식별자를 확인한다
        guard unzip.terminationStatus == 0,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw NSError(domain: "SessionBoard", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "받은 파일이 SessionBoard 앱이 아니에요."])
        }
        return app.path
    }

    // 이 앱이 완전히 끝난 뒤 바꾸기 작업을 하고 다시 켜는 작은 스크립트를 띄운다
    private func launchHelper(_ body: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let log = boardDir + "/update.log"
        let script = """
        #!/bin/bash
        exec >"\(log)" 2>&1
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        \(body)
        open "\(Bundle.main.bundlePath)"
        """
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("sessionboard-update.sh").path
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/bash")
        helper.arguments = [path]
        try helper.run()
    }
}
