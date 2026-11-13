import Foundation

/// Renders Codex pet atlases for the Pollen Robotics robots.
///
///     render-pets [--pet <id>]... [--view front|three-quarter] [--output <dir>] [--frames <dir>]
///                 [--raw <dir>] [--mask <dir>] [--models <dir>]
///
/// Writes `<output>/<id>/spritesheet.png` and `<output>/<id>/pet.json` for each pet,
/// in `Build/render` by default.
/// The manifest names `spritesheet.webp`, which `Scripts/package.py` makes from the PNG.
/// With `--frames`, it also writes each cell as its own image. With `--raw`, it writes each
/// cell at twice the size with no outline, for the pixel-art pipeline. With `--mask`, it also
/// writes Microduck's part mask: each cell again, cropped the same way, with each colorable part
/// in one flat color, and `parts.json`, which names the parts and their colors.
/// Microduck's idle, waving, jumping, waiting, working, and review rows turn
/// three-quarters toward screen right; with `--view front`, they face the viewer.
@MainActor func run() async throws {
    var pets: [PetID] = []
    var output = URL(fileURLWithPath: "Build/render")
    var frames: URL?
    var raw: URL?
    var mask: URL?
    var models = URL(fileURLWithPath: "Resources/Models")
    var view = MicroduckChoreography.View.threeQuarter
    var arguments = CommandLine.arguments.dropFirst()
    while let argument = arguments.popFirst() {
        switch argument {
        case "--pet":
            guard let value = arguments.popFirst(), let pet = PetID(rawValue: value) else {
                throw UsageError("--pet takes one of: \(PetID.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            pets.append(pet)
        case "--output":
            guard let value = arguments.popFirst() else { throw UsageError("--output takes a directory") }
            output = URL(fileURLWithPath: value)
        case "--frames":
            guard let value = arguments.popFirst() else { throw UsageError("--frames takes a directory") }
            frames = URL(fileURLWithPath: value)
        case "--mask":
            guard let value = arguments.popFirst() else { throw UsageError("--mask takes a directory") }
            mask = URL(fileURLWithPath: value)
        case "--raw":
            guard let value = arguments.popFirst() else { throw UsageError("--raw takes a directory") }
            raw = URL(fileURLWithPath: value)
        case "--view":
            guard let value = arguments.popFirst(), let choice = MicroduckChoreography.View(rawValue: value) else {
                throw UsageError("--view takes front or three-quarter")
            }
            view = choice
        case "--models":
            guard let value = arguments.popFirst() else { throw UsageError("--models takes a directory") }
            models = URL(fileURLWithPath: value)
        default:
            throw UsageError("Unknown argument: \(argument)")
        }
    }
    if pets.isEmpty { pets = PetID.allCases }

    let fileManager = FileManager.default
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    let renderer = try OffscreenRenderer(width: 1200, height: 1200)
    for pet in pets {
        let stage = try await PetStage(pet: pet, models: models)
        stage.aimCamera(at: [0, 1.1, 0], distance: 5.8)
        renderer.show(stage.root, camera: stage.camera, environment: stage.environment)
        let choreography: any Choreography = switch pet {
        case .microduck: MicroduckChoreography(view: view)
        case .reachyMini: ReachyMiniChoreography()
        }
        var petFrames: URL?
        if let frames {
            let directory = frames.appendingPathComponent(pet.rawValue)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            petFrames = directory
        }
        var petRaw: URL?
        if let raw {
            let directory = raw.appendingPathComponent(pet.rawValue)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            petRaw = directory
        }
        // Only Microduck has a part mask, for its pixel art.
        var petMask: (parts: PartMask, directory: URL)?
        if let mask, pet == .microduck {
            let directory = mask.appendingPathComponent(pet.rawValue)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            petMask = (PartMask(model: stage.model, parts: PartMask.microduck), directory)
        }
        let atlas = try await AtlasBuilder.build(stage: stage, choreography: choreography, renderer: renderer,
                                                 targetHeight: pet.targetHeight, framesDirectory: petFrames,
                                                 rawDirectory: petRaw, mask: petMask)
        let directory = output.appendingPathComponent(pet.rawValue)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try atlas.writePNG(to: directory.appendingPathComponent("spritesheet.png"))
        let manifest = PetManifest(id: pet.rawValue, displayName: pet.displayName, description: pet.description)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try (encoder.encode(manifest) + Data("\n".utf8)).write(to: directory.appendingPathComponent("pet.json"))
        print("Wrote \(directory.path)")
    }
}

/// The Codex pet manifest. Version 2 adds the two rows of look directions.
struct PetManifest: Encodable {
    let id: String
    let displayName: String
    let description: String
    var spriteVersionNumber = 2
    var spritesheetPath = "spritesheet.webp"
}

struct UsageError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

extension PetID {
    /// The neutral pose's height in the cell, in pixels. Taller poses shrink every frame to fit.
    var targetHeight: Double {
        switch self {
        case .microduck: 168
        case .reachyMini: 184
        }
    }
}

do {
    try await run()
} catch {
    FileHandle.standardError.write(Data("render-pets: \(error)\n".utf8))
    exit(1)
}
