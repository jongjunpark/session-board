// 설정 창 — 일반 · 백그라운드 작업 · 업데이트 · 관리
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var config = BoardConfig.shared
    @State private var launchAtLogin = Installer.launchAtLogin
    @State private var hooksInstalled = Installer.hooksInstalled(.claude)
    @State private var codexInstalled = Installer.hooksInstalled(.codex)
    @State private var menuBarEnabled = MenuBarController.enabled

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        Installer.setLaunchAtLogin(on)
                        launchAtLogin = Installer.launchAtLogin
                    }
                Toggle("메뉴 막대에 표시", isOn: $menuBarEnabled)
                    .onChange(of: menuBarEnabled) { _, on in MenuBarController.current?.setEnabled(on) }
            }

            Section {
                Toggle("장시간 실행 알림", isOn: $config.bgWarnEnabled)
                Picker("알림 시간", selection: $config.bgWarnMinutes) {
                    ForEach(BoardConfig.bgWarnChoices, id: \.self) { minutes in
                        Text(BoardConfig.label(minutes)).tag(minutes)
                    }
                }
                .disabled(!config.bgWarnEnabled)
            } header: {
                Text("백그라운드 작업")
            } footer: {
                Text("설정한 시간이 지나도 작업이 끝나지 않으면 알려 드려요. \"더 기다리기\"를 누르면 같은 시간만큼 다시 기다려요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("업데이트") {
                Toggle("업데이트 알림", isOn: $updater.notifyEnabled)
                LabeledContent("업데이트 확인") {
                    HStack(spacing: 8) {
                        if updater.status == .checking || updater.status == .installing {
                            ProgressView().controlSize(.small)
                        }
                        Button("지금 확인") {
                            Task { await updater.check(userInitiated: true) }
                        }
                        .disabled(updater.status == .checking || updater.status == .installing)
                    }
                }
                LabeledContent("버전") {
                    HStack(spacing: 8) {
                        Text(updater.currentVersion).foregroundStyle(.secondary)
                        if let release = updater.available {
                            Button("\(release.version)로 업데이트") { updater.confirmInstall(release) }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Claude Code 연동") {
                    HStack(spacing: 8) {
                        Text(hooksInstalled ? "연결됨" : "연결 안 됨").foregroundStyle(.secondary)
                        if hooksInstalled {
                            Button("연결 해제") { run { try Installer.uninstallHooks() } }
                        } else {
                            Button("연결") { run { try Installer.installHooks() } }
                        }
                    }
                }
                if HookTarget.codexAvailable {
                    LabeledContent("Codex 연동") {
                        HStack(spacing: 8) {
                            Text(codexInstalled ? "연결됨" : "연결 안 됨").foregroundStyle(.secondary)
                            if codexInstalled {
                                Button("연결 해제") { run { try Installer.uninstallHooks(.codex) } }
                            } else {
                                Button("연결") { run { try Installer.installHooks(.codex) } }
                            }
                        }
                    }
                }
                LabeledContent("SessionBoard 삭제") {
                    Button("삭제…") { Installer.uninstallEverything() }
                }
            } header: {
                Text("관리")
            } footer: {
                if HookTarget.codexAvailable {
                    Text("Codex 는 연결한 뒤 Codex 에서 새 훅을 한 번 허용해야 동작해요. 다음에 Codex 를 열 때 훅을 검토하라는 창이 뜨면 허용해 주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { Installer.alert("설정을 바꾸지 못했어요", error.localizedDescription) }
        hooksInstalled = Installer.hooksInstalled(.claude)
        codexInstalled = Installer.hooksInstalled(.codex)
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "SessionBoard 설정"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
