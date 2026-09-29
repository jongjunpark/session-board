// 화면 (떠 있는 창의 SwiftUI 뷰)
import AppKit
import SwiftUI

private enum Palette {
    static let needs = Color(red: 0.93, green: 0.62, blue: 0.10)
    static let running = Color.accentColor
    static let stale = Color.secondary
    static let done = Color(red: 0.19, green: 0.64, blue: 0.42)
}

struct BoardView: View {
    @ObservedObject var model: BoardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !model.collapsed {
                content
            } else if model.peek {
                peekContent
            }
        }
        .frame(width: model.collapsed ? (model.peek ? 210 : nil) : 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if !model.collapsed {
                Text("Claude 세션").font(.system(size: 12, weight: .semibold))
            }
            // 개수·접기 버튼은 늘 오른쪽 끝에 붙인다 (접고 펴고 호버해도 제자리).
            // 접힌 알약은 폭이 정해져 있지 않아서 빈칸을 넣으면 화면 끝까지 늘어나므로 뺀다
            if !model.collapsed || model.peek { Spacer(minLength: 0) }
            countChip("●", model.needs.count, Palette.needs)
            countChip("⟳", model.running.count, Palette.running)
            countChip("✓", model.done.count, Palette.done)
            if model.items.isEmpty && model.collapsed {
                Text("—").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Button {
                model.toggleCollapsed()
            } label: {
                Image(systemName: model.collapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.collapsed ? "펼치기" : "접기")
            .accessibilityLabel(model.collapsed ? "펼치기" : "접기")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        // 접힌 알약을 누르면 큰 화면으로 고정해서 펼친다
        .onTapGesture { if model.collapsed { model.toggleCollapsed() } }
        .contextMenu {
            if !model.done.isEmpty {
                Button("완료 전부 확인") { model.checkAllDone() }
            }
            Button("새로고침") { model.refresh() }
            Divider()
            Toggle("로그인 시 실행", isOn: Binding(
                get: { Installer.launchAtLogin },
                set: { Installer.setLaunchAtLogin($0) }
            ))
            if !Installer.hooksInstalled() {
                Button("Claude Code 훅 추가…") { Installer.askToInstallHooks() }
            }
            Button("세션 보드 제거…") { Installer.uninstallEverything() }
            Divider()
            Button("세션 보드 종료") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder
    private func countChip(_ symbol: String, _ count: Int, _ color: Color) -> some View {
        if count > 0 {
            Text("\(symbol) \(count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.16)))
                .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            Text(Installer.hooksInstalled()
                 ? "지금 도는 세션이 없어요"
                 : "Claude Code 훅이 없어서 세션을 볼 수 없어요.\n위쪽 줄을 오른쪽 클릭 → 훅 추가")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                section("확인 필요", model.needs, Palette.needs)
                section("진행중", model.running, .secondary)
                section("완료", model.done, .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 9)
        }
    }

    // 호버 때 뜨는 짧은 목록: 상태 아이콘 · 제목 · 시간 한 줄씩
    @ViewBuilder
    private var peekContent: some View {
        if model.items.isEmpty {
            Text("지금 도는 세션이 없어요")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.items) { item in
                    PeekRow(item: item, model: model)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 7)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [BoardItem], _ color: Color) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            ForEach(items) { item in
                BoardRow(item: item, model: model)
            }
        }
    }
}

// 유리 판은 내용 크기를 따라가고 창의 오른쪽 위에 붙는다. 크기 변화는 SwiftUI 가 부드럽게 그리고
// 창은 그 뒤에서 한 번에 맞춘다 (펼칠 땐 먼저 넓히고, 접을 땐 애니메이션이 끝난 뒤 줄인다).
struct AnchoredBoard: View {
    @ObservedObject var model: BoardModel

    var body: some View {
        let radius: CGFloat = model.collapsed && !model.peek ? 14 : 20
        BoardView(model: model)
            .modifier(GlassPanel(radius: radius))
            .padding(AnchoredBoard.margin) // 그림자가 퍼질 자리
            // 시스템 유리 그림자는 여백보다 넓게 퍼져 창 가장자리에서 뚝 끊긴다.
            // 정한 방향·폭만큼만 보이고 그 밖으로는 부드럽게 옅어지도록 흐린 마스크를 씌운다.
            .mask(
                ZStack {
                    // 유리 바깥: 아래·양옆으로만 그림자를 보이고 (위쪽은 유리 뒤로 숨김), 흐리게 (shadowOpacity) 하고 가장자리로 갈수록 옅게
                    RoundedRectangle(cornerRadius: radius + AnchoredBoard.shadowSide, style: .continuous)
                        .padding(EdgeInsets(
                            top: AnchoredBoard.margin + AnchoredBoard.shadowFeather * 2,
                            leading: AnchoredBoard.margin - AnchoredBoard.shadowSide,
                            bottom: AnchoredBoard.margin - AnchoredBoard.shadowBottom,
                            trailing: AnchoredBoard.margin - AnchoredBoard.shadowSide
                        ))
                        .blur(radius: AnchoredBoard.shadowFeather)
                        .opacity(AnchoredBoard.shadowOpacity)
                    // 유리 판 자체는 그대로
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .padding(AnchoredBoard.margin)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    static let margin: CGFloat = 20 // 창 가장자리까지의 여백
    static let shadowSide: CGFloat = 8 // 양옆 그림자 폭
    static let shadowBottom: CGFloat = 14 // 아래 그림자 폭 (위쪽은 없음)
    static let shadowFeather: CGFloat = 4 // 그림자가 옅어지는 부드러움
    static let shadowOpacity: Double = 0.45 // 그림자 진하기 (1 = 시스템 기본)
}

struct PeekRow: View {
    let item: BoardItem
    @ObservedObject var model: BoardModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            StateIcon(item: item).font(.system(size: 10)).frame(width: 12)
            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(item.short)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(item.state == "needs_input" ? Palette.needs : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.10 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.open(item) }
        .help(item.label)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button("세션 열기") { model.open(item) }
            if item.state == "done" { Button("확인 완료") { model.check(item) } }
        }
    }
}

// 상태 아이콘 (큰 화면·짧은 목록 공용)
struct StateIcon: View {
    let item: BoardItem

    var body: some View {
        switch item.state {
        case "needs_input":
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.needs)
        case "running":
            if item.stale {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Palette.stale)
            } else {
                ProgressView().controlSize(.mini)
            }
        default:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.done)
        }
    }
}

struct BoardRow: View {
    let item: BoardItem
    @ObservedObject var model: BoardModel
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StateIcon(item: item).frame(width: 14, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(item.label)
                    .font(.system(size: 11))
                    .foregroundStyle(labelColor)
                    .lineLimit(2)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.state == "done" {
                Button {
                    model.check(item)
                } label: {
                    Text("확인")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.done)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.done.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(Palette.done.opacity(0.35), lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("확인 완료 — 목록에서 치우기")
                .accessibilityLabel("확인 완료")
            }
            if item.bg_warn {
                // 늘 보이게 둔다: 멈춘 게 아니면 이걸 눌러 알림을 미룬다
                Button {
                    model.snooze(item)
                } label: {
                    Text("더 기다리기")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.needs)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.needs.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(Palette.needs.opacity(0.4), lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("정상으로 도는 중이면 15분 뒤에 다시 알려요")
                .accessibilityLabel("더 기다리기")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(card)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { model.open(item) }
        .help("눌러서 세션 열기")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button("세션 열기") { model.open(item) }
            if item.bg_warn {
                Button("더 기다리기 (15분 뒤 다시 알림)") { model.snooze(item) }
            }
            Button(item.state == "done" ? "확인 완료" : "목록에서 지우기") { model.check(item) }
        }
    }

    // 평소엔 유리 위에 바로 놓이고, 마우스를 올린 줄만 밝힌다. 확인 필요는 늘 호박색으로 살짝 물든다.
    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let tint = item.state == "needs_input" ? Palette.needs : Color.white
        return shape
            .fill(tint.opacity(item.state == "needs_input" ? (hovering ? 0.22 : 0.14) : (hovering ? 0.10 : 0)))
    }

    private var labelColor: Color {
        switch item.state {
        case "needs_input": return Palette.needs
        case "running": return item.stale ? Palette.stale : .secondary
        default: return .secondary
        }
    }
}

// macOS 26 이상은 시스템 유리(Liquid Glass), 그 아래는 흐림 배경 + 밝은 테두리로 대신한다
struct GlassPanel: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)) // 창이 커지는 동안 내용이 유리 밖으로 새지 않게
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                .background(VisualEffect())
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
