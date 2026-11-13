import RealityKit
import simd

/// One leg of Microduck, as offsets from the source model's standing pose.
struct LegPose: Sendable {
    /// Raises the foot by folding the hip and knee. One is a high step.
    var lift: Float = 0
    /// Swings the leg forward (positive) or back (negative), in radians at the hip.
    var swing: Float = 0
    /// Moves the leg out to the side (positive), in radians at the hip.
    var spread: Float = 0
    /// Tips the toe up (positive) or down (negative), in radians at the ankle.
    var toe: Float = 0
}

/// A full-body pose. Angles are in radians and use the viewer's frame:
/// positive pitch looks down, positive yaw looks toward screen right,
/// and positive roll tilts the top of the head toward screen right.
struct Pose: Sendable {
    /// The body's turn about the vertical axis. Positive values face screen right.
    var turn: Float = PetStage.restingYaw
    /// Height of the lowest part above the floor, in stage units. The robots are 1.95 units tall.
    var lift: Float = 0
    /// Position on the floor, in stage units: x toward screen right and y toward the viewer.
    var offset = SIMD2<Float>.zero
    /// Tips the whole robot forward (positive) or back, around its contact with the floor.
    var lean: Float = 0
    /// Tips the whole robot sideways. Positive values tip its top toward its own left,
    /// which is screen right when it faces the viewer.
    var sway: Float = 0
    /// Head pitch, yaw, and roll.
    var head = SIMD3<Float>.zero

    // Microduck
    /// Bends the neck forward (positive) or back, in radians. The head keeps its own pitch.
    var neck: Float = 0
    /// Opens the beak. One is wide open: 0.7 radians, about as wide as the real beak opens
    /// when it talks. Wide open, the lower beak clears the neck while `head.x + neck`,
    /// the head servo's turn, stays at or below about 0.45; tip the head back for wider quacks.
    var mouth: Float = 0
    /// Bends both knees and lowers the body. One is a deep crouch.
    /// The real knee stops at about 1.1.
    var crouch: Float = 0
    /// Moves both legs toward the real robot's sitting pose: the SIT keyframe of
    /// Pollen Robotics' sit-stand policy, with the knees folded 1.35 radians,
    /// the hips nearly as they stand, and the feet tipped up in front with the soles
    /// facing forward, so that the robot rests on its folded legs and the backs of its feet.
    /// One is seated. Combine it with no crouch.
    var sit: Float = 0
    var left = LegPose()
    var right = LegPose()

    // Reachy Mini
    /// Shifts the head on its platform, in stage units: x toward the robot's left,
    /// which is screen right when it faces the viewer, y up, and z forward.
    var headOffset = SIMD3<Float>.zero
    /// The angles of the antennas on screen left (x) and screen right (y), from upright.
    /// Positive values tip an antenna outward, away from the other one.
    var antennas = SIMD2<Float>.zero
}

@MainActor protocol PetRig: AnyObject {
    /// Poses every joint. The stage then places the robot on the floor.
    func apply(_ pose: Pose)
    /// The parts that can touch the floor. The stage sets the lowest point of any of them on the floor.
    var contacts: [Entity] { get }
    /// The joints that the last pose turned past the real robot's limits, described for a warning.
    var violations: [String] { get }
}

extension PetRig {
    var violations: [String] { [] }
}

// MARK: - Microduck

/// Turns Microduck's servos around their local axes, relative to the standing pose.
@MainActor final class MicroduckRig: PetRig {
    private var joints: [String: (entity: Entity, bind: Transform)] = [:]
    /// Microduck sits, kneels, and falls on its face, so any part can touch the floor.
    let contacts: [Entity]
    private(set) var violations: [String] = []

    /// Each servo's angle in the standing pose and its range, both from the upstream
    /// model (HOME in `microduck_constants.py` and the joint ranges in `robot_walk.xml`).
    /// The source model stands in this pose, so a servo's angle is its standing angle
    /// plus the turn that `apply` gives it. The right leg mirrors the left.
    private static let limits: [String: (home: Float, range: ClosedRange<Float>)] = [
        "neck_pitch": (0.3491, -1.5708...1.0472), "head_pitch": (0.3491, -1.5708...1.5708),
        "head_yaw": (0, -2.9671...2.9671), "head_roll": (0, -0.4363...0.4363),
        "left_hip_roll": (-0.0873, -0.3840...0.3840), "right_hip_roll": (0.0873, -0.3840...0.3840),
        "left_hip_pitch": (-0.4579, -1.5708...1.5708), "right_hip_pitch": (0.4579, -1.5708...1.5708),
        "left_knee": (-0.0049, -1.5708...1.5708), "right_knee": (0.0049, -1.5708...1.5708),
        "left_ankle": (0.4530, -1.5708...1.5708), "right_ankle": (-0.4530, -1.5708...1.5708),
    ]

    init(model: Entity) throws {
        let names = ["neck_pitch", "head_pitch", "head_yaw", "head_roll", "mouth_hinge"]
            + ["left", "right"].flatMap { side in
                ["hip_yaw", "hip_roll", "hip_pitch", "knee", "ankle"].map { "\(side)_\($0)" }
            }
        for name in names {
            guard let entity = model.findEntity(named: name) else { throw RigError.missingJoint(name) }
            joints[name] = (entity, entity.transform)
        }
        contacts = [model]
    }

    func apply(_ pose: Pose) {
        violations = []
        // A positive turn of the neck servo tips the neck forward. The head servo
        // turns the other way, so adding the neck's tip to it takes the tip back,
        // and `head.x` stays the head's own angle.
        rotate("neck_pitch", by: pose.neck)
        rotate("head_pitch", by: pose.head.x + pose.neck)
        rotate("head_yaw", by: pose.head.y)
        rotate("head_roll", by: pose.head.z)
        rotate("mouth_hinge", by: pose.mouth * 0.7, axis: [0, 1, 0])
        // The two legs mirror each other's joint signs. The knee servo turns the
        // other way from the hip and ankle servos, so a foot stays level while the
        // ankle offset equals the knee offset minus the hip offset.
        for (side, leg, sign) in [("left", pose.left, Float(-1)), ("right", pose.right, Float(1))] {
            // Folding turns the hip and knee servos negatively: the thigh tips forward
            // and the shin back, so the knee bends and the body lowers.
            let fold = -(pose.crouch * 0.55 + leg.lift * 0.6)
            let hip = fold + leg.swing
            let knee = fold * 2.6
            let ankle = knee - hip + leg.toe
            // The SIT keyframe's change from the standing pose, in the upstream model's
            // joint directions, which match a product photo of the real robot sitting.
            let sit = (hip: -0.05 * pose.sit, knee: -1.355 * pose.sit, ankle: 0.453 * pose.sit)
            rotate("\(side)_hip_pitch", by: sign * (hip + sit.hip))
            rotate("\(side)_knee", by: sign * (knee + sit.knee))
            rotate("\(side)_ankle", by: sign * (ankle + sit.ankle))
            rotate("\(side)_hip_roll", by: -sign * (leg.spread + 0.0873 * pose.sit))
        }
    }

    private func rotate(_ name: String, by angle: Float, axis: SIMD3<Float> = [0, 0, 1]) {
        guard let joint = joints[name] else { return }
        joint.entity.orientation = joint.bind.rotation * simd_quatf(angle: angle, axis: axis)
        if let limit = Self.limits[name], !limit.range.contains(limit.home + angle) {
            violations.append(String(format: "%@ %.2f (range %.2f to %.2f)", name, limit.home + angle,
                                     limit.range.lowerBound, limit.range.upperBound))
        }
    }
}

// MARK: - Reachy Mini

/// Moves Reachy Mini's head on its platform and swings each antenna on its motor.
@MainActor final class ReachyMiniRig: PetRig {
    private struct Antenna {
        let entity: Entity
        let bind: Transform
        let pivot: SIMD3<Float>
        /// The direction that tips the antenna outward.
        let axis: SIMD3<Float>
    }

    private let head: Entity
    private let headBind: Transform
    /// The viewer-frame axes in the head's parent space: right, up, and forward.
    private let axes: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>)
    private let antennas: [Antenna]
    let contacts: [Entity]

    init(model: Entity, character: Entity) throws {
        guard let head = model.findEntity(named: "Head"), let parent = head.parent,
              let body = model.findEntity(named: "Body") else { throw RigError.missingJoint("Head") }
        self.head = head
        headBind = head.transform
        func axis(_ direction: SIMD3<Float>, in entity: Entity) -> SIMD3<Float> {
            simd_normalize(entity.convert(direction: direction, from: character))
        }
        axes = (axis([1, 0, 0], in: parent), axis([0, 1, 0], in: parent), axis([0, 0, 1], in: parent))
        // Each antenna turns on a motor at the back of the head, around the axis
        // that points out of the face. The robot's right antenna is on screen left.
        antennas = try [("Cylinder_052", "Pivot_R_001", Float(1)), ("Cylinder_051", "Pivot_L_001", Float(-1))]
            .map { name, pivotName, outward in
                guard let entity = head.findEntity(named: name), let pivot = head.findEntity(named: pivotName)
                else { throw RigError.missingJoint(name) }
                return Antenna(entity: entity, bind: entity.transform,
                               pivot: pivot.visualBounds(relativeTo: head).center,
                               axis: outward * axis([0, 0, 1], in: head))
            }
        contacts = [body]
    }

    func apply(_ pose: Pose) {
        // Positive pitch looks down, so it turns around the viewer's right axis.
        let yaw = simd_quatf(angle: pose.head.y, axis: axes.up)
        let pitch = simd_quatf(angle: pose.head.x, axis: axes.right)
        let roll = simd_quatf(angle: -pose.head.z, axis: axes.forward)
        head.orientation = yaw * pitch * roll * headBind.rotation
        let shift = axes.right * pose.headOffset.x + axes.up * pose.headOffset.y + axes.forward * pose.headOffset.z
        head.position = headBind.translation + shift / head.parent!.scale(relativeTo: nil).x
        for (antenna, angle) in zip(antennas, [pose.antennas.x, pose.antennas.y]) {
            let turn = simd_quatf(angle: angle, axis: antenna.axis)
            let matrix = Transform(translation: antenna.pivot).matrix
                * Transform(rotation: turn).matrix
                * Transform(translation: -antenna.pivot).matrix
                * antenna.bind.matrix
            antenna.entity.transform = Transform(matrix: matrix)
        }
    }
}

enum RigError: Error {
    case missingJoint(String)
}
