import Foundation
import Testing
@testable import PalmierPro

@Suite("Gateway catalog")
@MainActor
struct GatewayCatalogTests {
    @Test func bundledTemplateDecodes() throws {
        let data = try GatewayCatalog.templateData()
        let all: Set<String> = ["protolabs/qwen-image", "protolabs/qwen-image-turbo",
                                "protolabs/ideogram-4", "protolabs/ltx2-video"]
        let entries = try GatewayCatalog.entries(fromTemplate: data, availableAliases: all)
        #expect(entries.count == 4)
        #expect(entries.contains { $0.kind == .video && $0.id == "protolabs/ltx2-video" })
    }

    @Test func absentImageAliasesAreDropped_videoKept() throws {
        let data = try GatewayCatalog.templateData()
        let entries = try GatewayCatalog.entries(
            fromTemplate: data,
            availableAliases: ["protolabs/qwen-image", "protolabs/qwen-image-turbo"]
        )
        let ids = Set(entries.map(\.id))
        #expect(!ids.contains("protolabs/ideogram-4"))
        #expect(ids.contains("protolabs/ltx2-video"), "video entries bypass /model/info (bridge-served)")
        #expect(ids.count == 3)
    }

    @Test func videoCapsMatchTheContract() throws {
        let data = try GatewayCatalog.templateData()
        let entries = try GatewayCatalog.entries(fromTemplate: data, availableAliases: [])
        let video = try #require(entries.first(where: { $0.kind == .video }))
        guard case .video(let caps) = video.uiCapabilities else {
            Issue.record("video entry lacks video caps"); return
        }
        #expect(caps.supportsFirstFrame, "I2V via input_reference must be offered")
        #expect(!caps.supportsLastFrame, "no end-frame on the gateway path")
        #expect(caps.maxReferenceImages == 0 && caps.maxReferenceVideos == 0 && caps.maxReferenceAudios == 0)
        #expect(!caps.requiresSourceVideo)
    }
}

@Suite("Gateway size mapping")
struct GatewaySizeMappingTests {
    @Test func explicitResolutionWins() {
        #expect(GatewayGenerationRunner.size(resolution: "1024x768", aspectRatio: "16:9") == "1024x768")
    }

    @Test func aspectRatioMapsToNativeBucket() {
        #expect(GatewayGenerationRunner.size(resolution: nil, aspectRatio: "16:9") == "1664x928")
        #expect(GatewayGenerationRunner.size(resolution: "", aspectRatio: "9:16") == "928x1664")
        #expect(GatewayGenerationRunner.size(resolution: nil, aspectRatio: "1:1") == "1328x1328")
    }

    @Test func unknownAspectFallsThroughToNil() {
        #expect(GatewayGenerationRunner.size(resolution: nil, aspectRatio: "21:9") == nil)
        #expect(GatewayGenerationRunner.size(resolution: nil, aspectRatio: nil) == nil)
    }
}
