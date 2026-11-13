import AppKit
import Metal
import RealityKit

/// Renders a RealityKit scene into a transparent bitmap without a window.
@MainActor final class OffscreenRenderer {
    let width: Int
    let height: Int
    private let renderer: RealityRenderer
    private let texture: any MTLTexture
    private let output: RealityRenderer.CameraOutput

    init(width: Int, height: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError.noTexture }
        self.width = width
        self.height = height
        self.texture = texture
        output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        renderer.cameraSettings.antialiasing = .multisample4X
        // Like the app's ARView, tone-map the light, so that white shells keep their shading.
        renderer.cameraSettings.isToneMappingEnabled = true
    }

    /// Tone-maps the light. A part mask turns it off, so that its flat colors stay exact.
    var toneMapping: Bool {
        get { renderer.cameraSettings.isToneMappingEnabled }
        set { renderer.cameraSettings.isToneMappingEnabled = newValue }
    }

    func show(_ root: Entity, camera: Entity, environment: EnvironmentResource) {
        renderer.entities.removeAll()
        renderer.entities.append(contentsOf: [root])
        renderer.activeCamera = camera
        renderer.lighting.resource = environment
        renderer.lighting.intensityExponent = 1
    }

    /// Renders one frame and returns it as a premultiplied sRGB image.
    func render() async throws -> CGImage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            do {
                try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in
                    continuation.resume()
                })
            } catch {
                continuation.resume(throwing: error)
            }
        }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&pixels, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent)
        else { throw RenderError.noImage }
        return image
    }

    enum RenderError: Error { case noMetalDevice, noTexture, noImage }
}
