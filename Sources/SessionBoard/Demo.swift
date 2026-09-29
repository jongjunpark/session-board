// 데모 모드 (`SessionBoard --demo`) — README 스크린샷용 예시 세션.
// 실제 기록·설정·훅·업데이트·메뉴 막대를 건드리지 않고, 창만 예시 데이터로 띄운다.
import Foundation

let demoMode = CommandLine.arguments.contains("--demo")

enum DemoData {
    static let items: [BoardItem] = [
        item("demo-1", "결제 API 리팩터링", "needs_input", agent: "codex", reason: "질문에 답해 주세요",
             label: "질문에 답해 주세요", short: "확인 필요"),
        item("demo-2", "E2E 테스트 정리", "needs_input",
             label: "백그라운드 작업 16분째 · 멈췄는지 확인해 보세요", short: "백그라운드 16분",
             bgCount: 1, bgWarn: true),
        item("demo-3", "대시보드 차트 개선", "running", agent: "codex", label: "12분째", short: "12분"),
        item("demo-4", "문서 사이트 빌드 수정", "running", label: "백그라운드 작업 3분째", short: "백그라운드 3분",
             bgCount: 1),
        item("demo-5", "로그인 버그 수정", "done", summary: "PR #128 을 올렸어요. 테스트 42개가 모두 통과했어요.",
             label: "3분 전 끝남", short: "3분 전"),
        item("demo-6", "API 문서 번역", "done", kind: "codex", agent: "codex", summary: "영문 문서 12개를 번역해 docs/ko 에 넣었어요.",
             label: "터미널 · docs · 1시간 전 끝남", short: "1시간 전"),
    ]

    private static func item(
        _ id: String, _ title: String, _ state: String,
        kind: String = "app", agent: String = "claude", reason: String = "", summary: String = "",
        label: String, short: String, bgCount: Int = 0, bgWarn: Bool = false
    ) -> BoardItem {
        BoardItem(
            session_id: id, kind: kind, local_id: "", app_bundle: "",
            title: title, state: state, reason: reason, summary: summary, stale: false,
            label: label, short: short, bg_count: bgCount, bg_warn: bgWarn, agent: agent
        )
    }
}
