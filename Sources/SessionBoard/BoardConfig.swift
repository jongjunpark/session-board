// 앱과 훅 스크립트가 함께 읽는 설정 — ~/.claude/session-board/config.json
import Foundation

@MainActor
final class BoardConfig: ObservableObject {
    static let shared = BoardConfig()
    static let bgWarnChoices = [5, 10, 15, 20, 30, 60] // 분

    private let path = boardDir + "/config.json"

    // 백그라운드 작업이 오래 돌면 확인 필요로 올리고 알릴지
    @Published var bgWarnEnabled = true { didSet { save() } }
    // 그 기준 시간이자 "더 기다리기"로 미루는 시간 (분)
    @Published var bgWarnMinutes = 15 { didSet { save() } }

    private var loading = false

    private init() {
        loading = true
        defer { loading = false }
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        bgWarnEnabled = json["bgWarnEnabled"] as? Bool ?? true
        if let minutes = json["bgWarnMinutes"] as? Int, Self.bgWarnChoices.contains(minutes) {
            bgWarnMinutes = minutes
        }
    }

    // 스크립트가 읽을 수 있게 파일에 쓴다 (처음 실행 때도 기본값으로 만들어 둔다)
    func save() {
        guard !loading else { return }
        let json: [String: Any] = ["bgWarnEnabled": bgWarnEnabled, "bgWarnMinutes": bgWarnMinutes]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? FileManager.default.createDirectory(atPath: boardDir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    static func label(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)시간" : "\(minutes)분"
    }
}
