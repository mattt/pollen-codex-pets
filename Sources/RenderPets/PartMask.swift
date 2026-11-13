import AppKit
import RealityKit

/// The parts of a robot that a buyer could color, each drawn in one flat color with no lighting,
/// so that the pixel art can tell which part each pixel belongs to.
@MainActor final class PartMask {
    struct Part {
        let name: String
        /// The mask color, as sRGB hex. Every part's color is far from every other's.
        let color: String
        /// The model's entity names, without the numeric suffix that the USD import adds.
        let entities: Set<String>
    }

    /// Microduck's parts. Every entity that no part names belongs to `servos`.
    static let microduck: [Part] = [
        Part(name: "head", color: "#ff0000", entities: ["top_head_shell"]),
        Part(name: "beak", color: "#ff8000", entities: ["jaw", "jaw_soft", "soft_mouth_top"]),
        // The underside of the head, which shows inside the mouth when the beak opens.
        Part(name: "mouth", color: "#ff00ff", entities: ["bottom_head_shell"]),
        Part(name: "ring", color: "#ffff00", entities: ["noenoeil"]),
        Part(name: "lens", color: "#00ffff", entities: ["lens", "m12_lens_holder"]),
        Part(name: "face", color: "#0000ff", entities: ["face_part"]),
        Part(name: "body", color: "#00ff00", entities: ["right_shell", "left_shell"]),
        Part(name: "thighs", color: "#006000", entities: ["upper_leg_left", "upper_leg_right"]),
        Part(name: "brackets", color: "#ffffff",
             entities: ["hip_l", "leg", "upper_leg_rigidity_plate", "power_support", "np_f970"]),
        Part(name: "feet", color: "#800000", entities: ["foot_left", "foot_right"]),
        Part(name: "ankles", color: "#00a0a0", entities: ["ankle_left", "ankle_right"]),
        Part(name: "soles", color: "#ff80c0", entities: ["sole_left", "sole_right"]),
        Part(name: "servos", color: "#606060", entities: []),
    ]

    private let parts: [Part]
    private var originals: [(entity: ModelEntity, materials: [any RealityKit.Material])] = []
    private var masks: [(entity: ModelEntity, material: UnlitMaterial)] = []

    init(model: Entity, parts: [Part]) {
        self.parts = parts
        func walk(_ entity: Entity) {
            if let modelEntity = entity as? ModelEntity, let component = modelEntity.model {
                let base = entity.name.replacingOccurrences(of: #"_\d+$"#, with: "", options: .regularExpression)
                let part = parts.first { $0.entities.contains(base) } ?? parts.first { $0.entities.isEmpty }!
                originals.append((modelEntity, component.materials))
                masks.append((modelEntity, UnlitMaterial(color: Self.color(part.color))))
            }
            for child in entity.children { walk(child) }
        }
        walk(model)
    }

    /// Draws every part in its mask color, or restores the model's own materials.
    func show(_ on: Bool) {
        for (index, (entity, material)) in masks.enumerated() {
            guard var component = entity.model else { continue }
            component.materials = on ? component.materials.map { _ in material } : originals[index].materials
            entity.model = component
        }
    }

    /// The parts and their mask colors, as JSON, for the pixel-art pipeline.
    func manifest() throws -> Data {
        let entries = parts.map { ["name": $0.name, "color": $0.color] }
        return try JSONSerialization.data(withJSONObject: ["parts": entries], options: [.prettyPrinted, .sortedKeys])
    }

    private static func color(_ hex: String) -> NSColor {
        let value = Int(hex.dropFirst(), radix: 16)!
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
