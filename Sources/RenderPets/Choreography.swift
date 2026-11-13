import Foundation

/// The nine animation rows of a Codex pet, in atlas order.
enum PetState: Int, CaseIterable, Sendable {
    case idle, runningRight, runningLeft, waving, jumping, failed, waiting, running, review

    var name: String {
        switch self {
        case .idle: "idle"
        case .runningRight: "running-right"
        case .runningLeft: "running-left"
        case .waving: "waving"
        case .jumping: "jumping"
        case .failed: "failed"
        case .waiting: "waiting"
        case .running: "running"
        case .review: "review"
        }
    }

    var frameCount: Int {
        switch self {
        case .idle: 6
        case .runningRight, .runningLeft: 8
        case .waving: 4
        case .jumping: 5
        case .failed: 8
        case .waiting, .running, .review: 6
        }
    }
}

/// Poses for every cell of the atlas.
@MainActor protocol Choreography {
    /// The pose for one frame of a state.
    func pose(_ state: PetState, frame: Int) -> Pose
    /// The pose for a look direction. Zero degrees is up; angles run clockwise.
    func look(_ degrees: Float) -> Pose
    /// The rest pose. Codex shows it when the pointer is too close to choose a direction.
    var neutral: Pose { get }
}

extension Choreography {
    var neutral: Pose { Pose() }
}

/// The phase of `frame` in a loop of `count` frames, in radians.
private func phase(_ frame: Int, of count: Int) -> Float {
    2 * .pi * Float(frame) / Float(count)
}

/// The value for `frame` from a list of keyed values, one per frame.
private func key(_ values: [Float], _ frame: Int) -> Float {
    values[min(frame, values.count - 1)]
}

// MARK: - Microduck

/// Microduck has a large head on a long neck, a beak that opens, and two legs.
/// Like the real robot, it stands with its knees bent, its body low,
/// and its head held forward and level. Every pose is an offset from that rest posture.
/// It walks, sits, and falls on its face; it can't jump, and its feet don't wave.
/// Every joint stays within the real robot's range; the renderer warns if one doesn't.
struct MicroduckChoreography: Choreography {
    /// Which way the rows that stay in place face.
    enum View: String {
        /// Toward the viewer, like the look directions.
        case front
        /// Three-quarters toward screen right, a little less than the walk, which shows
        /// the head held forward on its neck and the thigh shells, as the walk does.
        case threeQuarter = "three-quarter"
    }

    var view = View.threeQuarter

    /// The turn for idle, waving, jumping, waiting, working, and review.
    var facing: Float { view == .front ? PetStage.restingYaw : 0.55 }

    /// The real robot's standing posture. Compared with the front and side of
    /// Pollen Robotics' footage, a half crouch and a neck tipped 0.45 radians forward
    /// match its low body and forward head, and leave the open beak clear of the neck.
    static let rest: Pose = {
        var pose = Pose()
        pose.crouch = 0.5
        pose.neck = 0.45
        return pose
    }()

    var neutral: Pose { Self.rest }

    func pose(_ state: PetState, frame i: Int) -> Pose {
        var pose = Self.rest
        pose.turn = facing
        switch state {
        case .idle:
            // The ChatGPT app plays idle six times slower than the contract's timings,
            // about 6.6 seconds a loop, so each frame is a beat of its own: rest,
            // a breath in and out with the head a beat late, a glance aside,
            // a beak click while it looks, and a settle back to the front.
            pose.crouch += key([0, -0.05, 0.1, 0.05, 0.05, 0.02], i)
            pose.neck += key([0, -0.02, 0.05, 0.04, 0.04, 0.01], i)
            pose.head = [key([0, -0.04, 0.03, 0, 0, 0.01], i),
                         key([0, 0, 0, 0.3, 0.3, 0.04], i),
                         key([0, 0, 0.02, 0.1, 0.1, 0.03], i)]
            pose.mouth = key([0, 0, 0, 0, 0.45, 0], i)

        case .runningRight, .runningLeft:
            // The real gait, three-quarters on, in the shape of the built-in Codex pets' walks:
            // frames 6, 7, and 0 are the neutral walking stance, both feet flat and together,
            // so the 220 ms hold on frame 7 reads as standing for a beat between strides.
            // Frames 1 to 5 are one full stride, short and low: the left foot steps forward
            // as the right pushes back, both land on frame 3 with a dip, and the right steps
            // up to rejoin the left. The body waddles over the standing foot,
            // and the head bobs a beat behind.
            let direction: Float = state == .runningRight ? 1 : -1
            pose.turn = direction * 0.7
            pose.lean = 0.08
            pose.left = LegPose(lift: key([0, 0.07, 0.28, 0, 0, 0, 0, 0], i),
                                swing: key([0, 0.03, 0.14, 0.2, 0.12, 0.03, 0, 0], i))
            pose.right = LegPose(lift: key([0, 0, 0, 0, 0.26, 0.07, 0, 0], i),
                                 swing: key([0, -0.03, -0.14, -0.2, -0.12, -0.03, 0, 0], i))
            pose.sway = key([0, -0.015, -0.06, 0, 0.06, 0.015, 0, 0], i)
            pose.crouch += key([-0.015, -0.005, 0.03, 0.07, 0.03, 0.005, 0.015, 0], i)
            pose.neck += key([-0.03, -0.01, 0.08, 0.03, 0.06, 0.01, 0.03, 0], i)
            pose.head = [key([0.01, 0, -0.04, 0, -0.03, -0.01, -0.01, 0], i), 0,
                         key([0, 0.02, 0.04, 0, -0.04, -0.02, 0, 0], i)]
            pose.mouth = key([0.1, 0.12, 0.2, 0.12, 0.2, 0.12, 0.12, 0.1], i)

        case .waving:
            // Hello with the beak: a dip of the head, then head up with a wide-open quack
            // and a tilt that carries on as the beak closes, then a settle.
            pose.crouch += key([0.12, -0.08, 0, 0.02], i)
            pose.neck += key([0.15, -0.2, -0.1, 0], i)
            pose.head = [key([0.15, -0.3, -0.15, 0.02], i), 0, key([0, 0.15, 0.22, 0.08], i)]
            pose.mouth = key([0, 1, 0.5, 0], i)

        case .jumping:
            // Microduck can't jump, so it celebrates in place: a deep squash,
            // a tall stretch with the neck back and a big quack, a happy wiggle,
            // and a settle that Codex holds.
            pose.crouch += key([0.5, -0.45, -0.2, -0.1, 0.05], i)
            pose.neck += key([0.24, -0.45, -0.2, -0.1, 0], i)
            pose.lean = key([0.05, -0.05, 0, 0, 0], i)
            pose.sway = key([0, 0, -0.07, 0.07, 0], i)
            pose.head = [key([0.1, -0.4, -0.2, -0.1, 0], i), 0, key([0, 0, 0.2, -0.2, 0.05], i)]
            pose.mouth = key([0, 1, 0.7, 0.3, 0], i)

        case .failed:
            // A gasp with the beak open, a wobble, then the knees give way:
            // Microduck drops into a squat and slumps forward until its face is on the floor,
            // as the real robot does when it tips over. Codex holds the face-down pose.
            // A side view shows the slump; from the front, the head hides the body.
            pose.turn = 0.9
            pose.crouch = key([0.45, 0.5, 0.55, 1.0, 1.1, 1.1, 1.1, 1.1], i)
            pose.lean = key([-0.04, 0.05, 0.1, 0.2, 0.25, 0.6, 0.95, 1.0], i)
            pose.sway = key([0, 0.08, -0.08, 0, 0, 0, 0, 0], i)
            pose.neck = key([0.25, 0.4, 0.45, 0.6, 0.65, 0.65, 0.65, 0.65], i)
            pose.head = [key([-0.25, -0.1, 0, 0.2, 0.4, 0.5, 0.55, 0.55], i), 0,
                         key([0, -0.15, 0.15, 0.05, 0, 0, 0, 0], i)]
            pose.mouth = key([0.8, 0.4, 0.2, 0, 0, 0, 0, 0], i)
            // The slump carries the robot forward; slide it back to the middle of the cell.
            pose.offset = [key([0, 0, 0, -0.05, -0.05, -0.25, -0.38, -0.4], i),
                           key([0, 0, 0, -0.1, -0.15, -0.3, -0.4, -0.4], i)]

        case .waiting:
            // Microduck sits down to wait, as the real robot sits: the trunk upright and low,
            // the legs folded under it, and the feet tipped up in front.
            // Alert, it looks up at the viewer, tilts its head one way,
            // gives a short call, then tilts the other way.
            pose.crouch = 0
            pose.sit = 1
            pose.neck = key([0.25, 0.25, 0.22, 0.25, 0.25, 0.25], i)
            pose.head = [key([-0.2, -0.22, -0.3, -0.22, -0.2, -0.2], i), 0,
                         key([0, 0.25, 0.28, -0.2, -0.25, 0.05], i)]
            pose.mouth = key([0, 0, 0.7, 0.2, 0, 0], i)

        case .running:
            // Busy chatter: the beak opens and closes on most frames
            // as the head bobs, turns, and tilts to make each point.
            pose.crouch += key([0, 0.03, 0, 0.03, 0, 0.01], i)
            pose.neck += key([0, 0.05, -0.05, 0.08, -0.05, 0], i)
            pose.sway = key([0, 0.02, 0, -0.02, 0, 0], i)
            pose.head = [key([-0.15, 0.05, -0.1, 0.08, -0.2, 0], i),
                         key([0.1, 0.05, -0.1, -0.05, 0.05, 0], i),
                         key([0.1, 0.04, -0.12, -0.05, 0.08, 0], i)]
            pose.mouth = key([0.9, 0.2, 0.7, 0.1, 0.8, 0], i)

        case .review:
            // It leans in and looks at the work with one eye, then the other,
            // draws back, pecks at it once as it picks things off the floor,
            // and nods with approval. The held last frame leans back in,
            // so that the loop returns to the first look without a jump.
            pose.lean = key([0.1, 0.1, 0, 0.22, 0.05, 0.08], i)
            pose.crouch += key([0.05, 0.05, 0.12, 0.25, 0, 0.04], i)
            pose.neck += key([0.15, 0.15, -0.05, 0.22, 0, 0.1], i)
            // The peck turns the head a little, so that the beak shows as it goes down.
            pose.head = [key([0.2, 0.2, -0.1, 0.45, -0.15, 0.12], i),
                         key([-0.35, 0.35, 0.1, 0.15, 0, -0.2], i),
                         key([0.2, -0.2, 0, 0, 0.08, 0.12], i)]
            pose.mouth = key([0, 0, 0, 0.2, 0.35, 0], i)
        }
        return pose
    }

    func look(_ degrees: Float) -> Pose {
        let angle = degrees * .pi / 180
        let (right, up) = (sin(angle), cos(angle))
        var pose = Self.rest
        // The looks always face the viewer. The head leads the turn; the body follows a little.
        pose.turn += 0.28 * right
        // Looking up tips the head back on the neck; looking down bows the neck too.
        pose.head = [up > 0 ? -0.6 * up : -0.55 * up, 0.75 * right, 0]
        pose.neck += up > 0 ? -0.15 * up : -0.2 * up
        return pose
    }
}

// MARK: - Reachy Mini

/// Reachy Mini stays on its base. Like the real robot, it turns its body,
/// moves its head on a platform that rotates and shifts, and swings two antennas.
struct ReachyMiniChoreography: Choreography {
    func pose(_ state: PetState, frame i: Int) -> Pose {
        var pose = Pose()
        switch state {
        case .idle:
            // Antennas drift and the head breathes.
            let t = phase(i, of: state.frameCount)
            pose.antennas = [0.06 * sin(t), 0.06 * sin(t + 1.2)]
            pose.head = [0.03 * sin(t), 0.04 * sin(t + 0.5), 0.03 * sin(t)]
            pose.headOffset.y = 0.01 * sin(t)

        case .runningRight, .runningLeft:
            // It can't travel, so it turns toward the way it's carried and bobs
            // its head in time, reaching ahead, with its antennas flapping.
            let direction: Float = state == .runningRight ? 1 : -1
            let t = phase(i, of: state.frameCount)
            pose.turn = direction * 0.85
            pose.head = [0.06 + 0.08 * cos(2 * t), 0.12, 0.06 * sin(t)]
            pose.headOffset = [0, 0.025 * abs(sin(t)), 0.03]
            pose.antennas = [0.3 + 0.2 * cos(2 * t), 0.3 + 0.2 * cos(2 * t + 0.6)]

        case .waving:
            // The antenna on screen right waves; the head tilts toward it.
            pose.antennas = [0.05, key([0.5, 1.0, 0.35, 0], i)]
            pose.head = [key([-0.04, -0.06, -0.06, 0], i), key([0.05, 0.1, 0.1, 0], i), key([0.08, 0.12, 0.12, 0.03], i)]

        case .jumping:
            // It can't jump, so it celebrates with a full turn of its body,
            // head up and antennas thrown wide.
            pose.turn += phase(i, of: state.frameCount)
            pose.head = [key([-0.12, -0.18, -0.18, -0.18, -0.08], i), 0, key([0.08, 0.12, -0.12, -0.08, 0.04], i)]
            pose.headOffset.y = key([0.02, 0.03, 0.03, 0.03, 0.01], i)
            let spread = key([0.5, 0.9, 1.0, 0.9, 0.4], i)
            pose.antennas = [spread, spread]

        case .failed:
            // Antennas droop, the head sinks and shakes no.
            let droop = key([0, 0.2, 0.5, 0.8, 1.05, 1.2, 1.3, 1.35], i)
            pose.antennas = [droop, droop * 0.95]
            pose.head = [key([0, 0.08, 0.16, 0.24, 0.3, 0.35, 0.38, 0.4], i),
                         key([0, 0, -0.2, 0.2, -0.15, 0.1, -0.04, 0], i),
                         key([0, 0, -0.02, -0.04, -0.06, -0.07, -0.08, -0.08], i)]
            pose.headOffset.y = key([0, -0.01, -0.02, -0.03, -0.04, -0.05, -0.06, -0.06], i)

        case .waiting:
            // A curious tilt toward the viewer; one antenna twitches like a question mark.
            pose.head = [-0.1, 0.04, 0.2]
            pose.antennas = [0.35, key([-0.1, 0.15, -0.1, 0.15, -0.1, 0], i)]
            pose.headOffset.y = key([0, 0.01, 0, 0.01, 0, 0], i)

        case .running:
            // Busy work: the antennas sweep like wipers while the head scans its task.
            let t = phase(i, of: state.frameCount)
            pose.antennas = [0.4 * sin(t), -0.4 * sin(t)]
            pose.head = [0.22, 0.2 * sin(t), 0]
            pose.headOffset.y = -0.02 + 0.01 * cos(2 * t)

        case .review:
            // Antennas point in with focus; the head leans in, inspects from each side, then nods.
            pose.antennas = [-0.12, -0.12]
            pose.headOffset = [key([0, -0.02, -0.02, 0.01, 0.02, 0], i), -0.01, 0.04]
            pose.head = [key([0.2, 0.2, 0.22, 0.2, 0.2, 0.3], i),
                         key([0, -0.15, -0.18, 0.05, 0.16, 0], i),
                         key([0.05, 0.15, 0.18, 0, -0.12, 0], i)]
        }
        return pose
    }

    func look(_ degrees: Float) -> Pose {
        let angle = degrees * .pi / 180
        let (right, up) = (sin(angle), cos(angle))
        var pose = Pose()
        pose.turn += 0.3 * right
        pose.head = [-0.55 * up, 0.7 * right, 0]
        pose.headOffset.y = 0.03 * up
        // The antennas trail behind the turn, spread when looking up, and close when looking down.
        pose.antennas = [0.15 * right + 0.18 * up, -0.15 * right + 0.18 * up]
        return pose
    }
}
