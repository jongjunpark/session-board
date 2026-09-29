// 설정 창 — 일반 · 백그라운드 작업 · 업데이트 · 관리
import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var config = BoardConfig.shared
    @State private var launchAtLogin = Installer.launchAtLogin
    @State private var hooksInstalled = Installer.hooksInstalled()
    @State private var menuBarEnabled = MenuBarController.enabled

    var body: some View {
        Form {
            Section("일반") {
                Toggle("로그인할 때 켜기", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        Installer.setLaunchAtLogin(on)
                        launchAtLogin = Installer.launchAtLogin
                    }
                Toggle("메뉴 막대에 표시", isOn: $menuBarEnabled)
                    .onChange(of: menuBarEnabled) { _, on in MenuBarController.current?.setEnabled(on) }
            }

            Section {
                Toggle("오래 걸리면 알림", isOn: $config.bgWarnEnabled)
                Picker("알림 기준 시간", selection: $config.bgWarnMinutes) {
                    ForEach(BoardConfig.bgWarnChoices, id: \.self) { minutes in
                        Text(BoardConfig.label(minutes)).tag(minutes)
                    }
                }
                .disabled(!config.bgWarnEnabled)
            } header: {
                Text("백그라운드 작업")
            } footer: {
                Text("백그라운드 작업이 이 시간보다 오래 돌면 확인 필요로 올리고 알려요. \"더 기다리기\"를 누르면 같은 시간만큼 미뤄요.")
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
                            Button("\(release.version) 로 업데이트") { updater.confirmInstall(release) }
                        }
                    }
                }
            }

            Section("관리") {
                LabeledContent("Claude Code 훅") {
                    HStack(spacing: 8) {
                        Text(hooksInstalled ? "설치됨" : "없음").foregroundStyle(.secondary)
                        if hooksInstalled {
                            Button("빼기") { run { try Installer.uninstallHooks() } }
                        } else {
                            Button("추가") { run { try Installer.installHooks() } }
                        }
                    }
                }
                LabeledContent("세션 보드 제거") {
                    Button("제거…") { Installer.uninstallEverything() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { Installer.alert("설정을 바꾸지 못했어요", error.localizedDescription) }
        hooksInstalled = Installer.hooksInstalled()
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
