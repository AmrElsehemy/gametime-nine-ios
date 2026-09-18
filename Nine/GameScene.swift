import SpriteKit
import GameTimeCore
import GameTimeExperience

final class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.961, green: 0.949, blue: 0.918, alpha: 1.0)

        let title = SKLabelNode(fontNamed: "SFProRounded-Semibold")
        title.text = "Nine"
        title.fontSize = 34
        title.fontColor = SKColor(white: 0.15, alpha: 1.0)
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 20)
        addChild(title)

        let status = SKLabelNode(fontNamed: "SFProRounded-Regular")
        status.text = "GameTimeKit \(GameTimeKit.version)"
        status.fontSize = 14
        status.fontColor = SKColor(white: 0.35, alpha: 1.0)
        status.position = CGPoint(x: size.width / 2, y: size.height / 2 - 24)
        addChild(status)
    }
}
