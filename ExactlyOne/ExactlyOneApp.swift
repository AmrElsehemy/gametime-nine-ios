import GameKit
import SpriteKit
import SwiftUI
import GameTimeCore
import GameTimeExperience

@main
struct ExactlyOneApp: App {
    var body: some Scene {
        WindowGroup {
            ExactlyOneRootView()
        }
    }
}

@MainActor
private struct ExactlyOneRootView: View {
    @StateObject private var shell = ExactlyOneShellModel()
    @State private var showsSettings = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SpriteView(scene: shell.scene)
                .ignoresSafeArea()

            if ExactlyOneCapturePreset.current == nil {
                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.28), in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                        }
                }
                .accessibilityLabel("Settings")
                .padding(.top, 14)
                .padding(.trailing, 14)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsSettings) {
            ExactlyOneSettingsView(
                onResetGameplay: {
                    shell.resetGameplay()
                }
            )
        }
    }
}

@MainActor
private final class ExactlyOneShellModel: ObservableObject {
    @Published private(set) var scene: SKScene

    init() {
        scene = Self.makeScene()
    }

    func resetGameplay() {
        let store = ExactlyOneProgressStore()
        _ = store.reset(levels: PrototypeLevels.production)
        UserDefaults.standard.removeObject(
            forKey: ExactlyOneTutorialCompletionStore.defaultKey
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
private struct ExactlyOneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("exactlyone.preferences.soundEnabled")
    private var soundEnabled = true

    @AppStorage("exactlyone.preferences.hapticsEnabled")
    private var hapticsEnabled = true

    @State private var showsResetConfirmation = false

    let onResetGameplay: () -> Void

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

                    Text("Reduce Motion follows your iPhone accessibility setting. Exactly One keeps all puzzle states readable without requiring motion.")
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
                            ExactlyOneGameCenterService.shared.authenticateIfNeeded()
                        }
                    }
                }

                Section("Help & Privacy") {
                    Link(
                        "Support",
                        destination: URL(string: "https://knowlly.games/support/exactly-one")!
                    )
                    Link(
                        "Report a Problem",
                        destination: URL(string: "https://knowlly.games/support/exactly-one?report=1")!
                    )
                    Link(
                        "Privacy",
                        destination: URL(string: "https://knowlly.games/privacy/exactly-one")!
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
}
