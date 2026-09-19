import GameKit
import SpriteKit
import StoreKit
import SwiftUI
import GameTimeCore
import GameTimeExperience

@main
struct NineApp: App {
    var body: some Scene {
        WindowGroup {
            NineRootView()
        }
    }
}

@MainActor
private struct NineRootView: View {
    @StateObject private var shell = NineShellModel()
    @State private var showsSettings = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(scene: shell.scene)
                .ignoresSafeArea()

            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.72))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Settings")
            .padding(.top, 14)
            .padding(.trailing, 14)
        }
        .sheet(isPresented: $showsSettings) {
            NineSettingsView(
                onResetGameplay: {
                    shell.resetGameplay()
                }
            )
        }
    }
}

@MainActor
private final class NineShellModel: ObservableObject {
    @Published private(set) var scene: SKScene

    init() {
        scene = Self.makeScene()
    }

    func resetGameplay() {
        let store = NineProgressStore()
        _ = store.reset(levels: PrototypeLevels.production)
        UserDefaults.standard.removeObject(
            forKey: NineTutorialCompletionStore.defaultKey
        )
        scene = Self.makeScene()
    }

    private static func makeScene() -> SKScene {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        return scene
    }
}

@MainActor
private struct NineSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("nine.preferences.soundEnabled")
    private var soundEnabled = true

    @AppStorage("nine.preferences.hapticsEnabled")
    private var hapticsEnabled = true

    @State private var restoreState: RestoreState = .idle
    @State private var showsResetConfirmation = false

    let onResetGameplay: () -> Void

    private enum RestoreState: Equatable {
        case idle
        case restoring
        case restored
        case failed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Experience") {
                    Toggle("Sound", isOn: $soundEnabled)
                    Toggle("Haptics", isOn: $hapticsEnabled)

                    LabeledContent("Reduce Motion") {
                        Text(reduceMotion ? "On" : "Off")
                            .foregroundStyle(.secondary)
                    }

                    Text("Reduce Motion follows your iPhone accessibility setting. Nine keeps all puzzle states readable without requiring motion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Game Center") {
                    LabeledContent("Status") {
                        Text(
                            GKLocalPlayer.local.isAuthenticated
                                ? "Connected"
                                : "Optional"
                        )
                        .foregroundStyle(.secondary)
                    }

                    Button("Open Game Center") {
                        if GKLocalPlayer.local.isAuthenticated {
                            GKAccessPoint.shared.trigger(state: .dashboard) {}
                        } else {
                            NineGameCenterService.shared.authenticateIfNeeded()
                        }
                    }
                }

                Section("Purchases") {
                    Button(restoreTitle) {
                        restorePurchases()
                    }
                    .disabled(restoreState == .restoring)

                    Text("Nine currently uses optional rewarded ads only. Restore Purchases is kept here for future entitlements and App Store consistency.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Help & Privacy") {
                    Link(
                        "Support",
                        destination: URL(string: "https://knowlly.games/support/nine")!
                    )
                    Link(
                        "Report a Problem",
                        destination: URL(string: "https://knowlly.games/support/nine?report=1")!
                    )
                    Link(
                        "Privacy",
                        destination: URL(string: "https://knowlly.games/privacy/nine")!
                    )
                }

                Section("About") {
                    LabeledContent("Version", value: versionText)
                    LabeledContent("Build", value: buildText)
                    LabeledContent("Publisher", value: "Knowlly Games")
                }

                Section {
                    Button("Reset Gameplay Data", role: .destructive) {
                        showsResetConfirmation = true
                    }
                } footer: {
                    Text("This clears local level progress, the active puzzle, daily/streak progress and onboarding completion. Sound and haptic preferences are kept.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Reset all local gameplay data?",
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset Gameplay Data", role: .destructive) {
                    onResetGameplay()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. Game Center achievements are not removed.")
            }
        }
    }

    private var versionText: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
    }

    private var buildText: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
    }

    private var restoreTitle: String {
        switch restoreState {
        case .idle:
            return "Restore Purchases"
        case .restoring:
            return "Restoring…"
        case .restored:
            return "Purchases Restored"
        case .failed:
            return "Restore Failed — Try Again"
        }
    }

    private func restorePurchases() {
        restoreState = .restoring
        Task { @MainActor in
            do {
                try await AppStore.sync()
                restoreState = .restored
            } catch {
                restoreState = .failed
            }
        }
    }
}
