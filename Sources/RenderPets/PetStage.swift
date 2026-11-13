import AppKit
import RealityKit
import simd

/// The robots that this tool renders.
enum PetID: String, CaseIterable, Sendable {
    case microduck
    case reachyMini = "reachy-mini"

    var displayName: String {
        switch self {
        case .microduck: "Microduck"
        case .reachyMini: "Reachy Mini"
        }
    }

    var description: String {
        switch self {
        case .microduck: "A little walking duck robot by Pollen Robotics."
        case .reachyMini: "A desktop robot by Pollen Robotics, with an expressive head and antennas."
        }
    }
}

/// One robot on a transparent stage, lit and framed like Pollen Pet's companion window.
@MainActor final class PetStage {
    nonisolated static let restingYaw: Float = -0.13
    static let fieldOfView: Float = 35

    let pet: PetID
    let root = Entity()
    /// Moves and turns the whole robot. Its origin is on the floor, below the robot's base.
    let character = Entity()
    let camera = PerspectiveCamera()
    let environment: EnvironmentResource
    let model: Entity
    private let rig: any PetRig

    init(pet: PetID, models: URL) async throws {
        self.pet = pet
        let folder = models.appendingPathComponent(pet.rawValue)
        async let lighting = StageLighting.environment()
        async let mesh = Entity(contentsOf: folder.appendingPathComponent("model.usdz"))
        (environment, model) = try await (lighting, mesh)

        let framing = try JSONDecoder().decode([String: [Float]].self,
            from: Data(contentsOf: folder.appendingPathComponent("framing.json")))
        guard let minimum = framing["min"], let maximum = framing["max"],
              minimum.count == 3, maximum.count == 3 else { throw StageError.invalidFraming }
        let low = SIMD3(minimum[0], minimum[1], minimum[2])
        let high = SIMD3(maximum[0], maximum[1], maximum[2])
        let base = SIMD3((low.x + high.x) / 2, low.y, (low.z + high.z) / 2)
        // Like the app, scale every robot to the same height on stage.
        let scale = 1.95 / (high.y - low.y)
        let orientation = Entity()
        orientation.addChild(model)
        orientation.scale = .init(repeating: scale)
        orientation.position = -base * scale
        character.addChild(orientation)
        character.orientation = simd_quatf(angle: Self.restingYaw, axis: [0, 1, 0])
        root.addChild(character)
        switch pet {
        case .microduck:
            try Self.paintMicroduck(model)
            rig = try MicroduckRig(model: model)
        case .reachyMini:
            rig = try ReachyMiniRig(model: model, character: character)
        }

        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        camera.camera.near = 0.1
        camera.camera.far = 80
        root.addChild(camera)
        StageLighting.apply(to: root)
    }

    /// Poses the robot, then sets it down so that its lowest part is `pose.lift` above the floor.
    func apply(_ pose: Pose) {
        rig.apply(pose)
        character.transform = Transform(rotation: simd_quatf(angle: pose.turn, axis: [0, 1, 0])
            * simd_quatf(angle: pose.lean, axis: [1, 0, 0])
            * simd_quatf(angle: -pose.sway, axis: [0, 0, 1]))
        let floor = rig.contacts.map { $0.visualBounds(relativeTo: root).min.y }.min() ?? 0
        character.position = [pose.offset.x, pose.lift - floor, pose.offset.y]
    }

    /// The joints that the last pose turned past the real robot's limits.
    var violations: [String] { rig.violations }

    /// Points the camera along the app's viewing direction from `distance` away.
    func aimCamera(at target: SIMD3<Float>, distance: Float) {
        let baseline = SIMD3<Float>(0, 2.0, 3.7) - SIMD3<Float>(0, 1.1, 0)
        camera.look(at: target, from: target + simd_normalize(baseline) * distance, relativeTo: nil)
    }

    /// Applies the app's default "Cream" colors: a cream shell with an orange beak and feet.
    /// Entities are matched by the mesh names in the model, without the numeric suffix
    /// that the import adds, which changes when upstream reorders a body's geoms.
    private static func paintMicroduck(_ model: Entity) throws {
        let cream = NSColor(srgbRed: 0xEE / 255.0, green: 0xE6 / 255.0, blue: 0xD2 / 255.0, alpha: 1)
        let orange = NSColor(srgbRed: 0xF1 / 255.0, green: 0x8B / 255.0, blue: 0x42 / 255.0, alpha: 1)
        var colors: [String: NSColor] = [
            "top_head_shell": cream, "bottom_head_shell": cream, "right_shell": cream, "left_shell": cream,
            "soft_mouth_top": orange, "jaw_soft": orange, "jaw": orange, "foot_left": orange, "foot_right": orange,
            "sole_left": orange, "sole_right": orange,
        ]
        // Upstream recolored these parts when it re-exported the CAD on September 1, 2026.
        // The pixel art was drawn from renders in their earlier colors, so the renderer keeps those,
        // as sRGB hex from the materials of microduck_rl at revision 1e79c29.
        let earlier: [String: Int] = [
            "ankle_left": 0xFAB601, "ankle_right": 0xFAB601, "bearing_roll": 0x43484D, "face_part": 0x596066,
            "hip_l": 0xE6E6E6, "leg": 0xCFDBE5, "motor_support": 0x43484D, "neck": 0xCCCCCC,
            "noenoeil": 0x43484D, "np_f970": 0xE6E6E6, "power_support": 0xE6E6E6,
            "seeed_bearing__configuration__22x16x4": 0xB6C2CC, "seeed_bearing__configuration_default": 0xB6C2CC,
            "trunk_base": 0x596066, "upper_leg_left": 0xDDDDDD, "upper_leg_right": 0xDDDDDD,
            "upper_leg_rigidity_plate": 0x89DAD3, "yaw2roll": 0xA5A5A5, "yaw_roll_motion": 0xC4E2F3,
        ]
        for (name, hex) in earlier {
            colors[name] = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                                   blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        var painted = Set<String>()
        func walk(_ entity: Entity) {
            let base = entity.name.replacingOccurrences(of: #"_\d+$"#, with: "", options: .regularExpression)
            if let color = colors[base], let modelEntity = entity as? ModelEntity, var component = modelEntity.model {
                component.materials = component.materials.map { original in
                    guard var material = original as? PhysicallyBasedMaterial else { return original }
                    material.baseColor = .init(tint: color)
                    return material
                }
                modelEntity.model = component
                painted.insert(base)
            }
            for child in entity.children { walk(child) }
        }
        walk(model)
        if let missing = colors.keys.sorted().first(where: { !painted.contains($0) }) {
            throw StageError.missingMesh(missing)
        }
    }

    enum StageError: Error { case invalidFraming, missingMesh(String) }
}

// MARK: - Lighting

/// The app's lighting: a soft sky-and-ground environment with one restrained key light.
@MainActor enum StageLighting {
    static func environment() async throws -> EnvironmentResource {
        let width = 256, height = 128
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            let t = Double(y) / Double(height - 1)
            let sky = SIMD3<Double>(0.78, 0.86, 0.98)
            let horizon = SIMD3<Double>(0.94, 0.93, 0.87)
            let ground = SIMD3<Double>(0.62, 0.68, 0.53)
            let color = t < 0.5 ? sky + (horizon - sky) * (t * 2) : horizon + (ground - horizon) * ((t - 0.5) * 2)
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(color.x * 255)
                pixels[i + 1] = UInt8(color.y * 255)
                pixels[i + 2] = UInt8(color.z * 255)
            }
        }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
            shouldInterpolate: true, intent: .defaultIntent)!
        return try await EnvironmentResource(equirectangular: image)
    }

    static func apply(to root: Entity) {
        let sun = DirectionalLight()
        sun.light.color = NSColor(srgbRed: 1, green: 0.95, blue: 0.85, alpha: 1)
        sun.light.intensity = 500
        sun.shadow = .init()
        sun.look(at: [0, 0, 0], from: [3, 6, 4], relativeTo: nil)
        root.addChild(sun)
    }
}
