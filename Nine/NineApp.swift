import SwiftUI
import SpriteKit
import GameTimeCore
import GameTimeExperience

@main
struct NineApp: App {
    private let scene: SKScene = {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        return scene
    }()

    var body: some Scene {
        WindowGroup {
            SpriteView(scene: scene)
                .ignoresSafeArea()
        }
    }
}
