import Foundation
import Testing
@testable import OperatorDesktop

@Test func codexBinarySettingsUsesDetectedPathWhenNoOverrideExists() throws {
    let settings = CodexBinarySettings(
        store: InMemoryCodexBinarySettingsStore(),
        detector: StubCodexBinaryDetector(detectedURL: URL(filePath: "/opt/homebrew/bin/codex"))
    )

    let configuration = try settings.configuration()

    #expect(configuration.detectedBinaryURL == URL(filePath: "/opt/homebrew/bin/codex"))
    #expect(configuration.overrideBinaryURL == nil)
    #expect(configuration.effectiveBinaryURL == URL(filePath: "/opt/homebrew/bin/codex"))
    #expect(configuration.displayPath == "/opt/homebrew/bin/codex")
}

@Test func codexBinarySettingsUsesAbsoluteOverrideBeforeDetectedPath() throws {
    let store = InMemoryCodexBinarySettingsStore()
    let settings = CodexBinarySettings(
        store: store,
        detector: StubCodexBinaryDetector(detectedURL: URL(filePath: "/usr/local/bin/codex"))
    )

    try settings.setOverridePath("/Applications/Codex.app/Contents/MacOS/codex")
    let configuration = try settings.configuration()

    #expect(store.overridePath == "/Applications/Codex.app/Contents/MacOS/codex")
    #expect(configuration.detectedBinaryURL == URL(filePath: "/usr/local/bin/codex"))
    #expect(configuration.overrideBinaryURL == URL(filePath: "/Applications/Codex.app/Contents/MacOS/codex"))
    #expect(configuration.effectiveBinaryURL == URL(filePath: "/Applications/Codex.app/Contents/MacOS/codex"))
    #expect(configuration.displayPath == "/Applications/Codex.app/Contents/MacOS/codex")
}

@Test func codexBinarySettingsRejectsRelativeOverridePath() throws {
    let settings = CodexBinarySettings(
        store: InMemoryCodexBinarySettingsStore(),
        detector: StubCodexBinaryDetector(detectedURL: URL(filePath: "/usr/local/bin/codex"))
    )

    #expect(throws: CodexBinarySettingsError.overrideMustBeAbsolute) {
        try settings.setOverridePath("bin/codex")
    }
}

@Test func codexBinarySettingsTrimsAndClearsOverridePath() throws {
    let store = InMemoryCodexBinarySettingsStore(overridePath: "/custom/codex")
    let settings = CodexBinarySettings(
        store: store,
        detector: StubCodexBinaryDetector(detectedURL: URL(filePath: "/usr/local/bin/codex"))
    )

    try settings.setOverridePath("   ")

    #expect(store.overridePath == nil)
    #expect(try settings.configuration().effectiveBinaryURL == URL(filePath: "/usr/local/bin/codex"))
}

@Test func codexBinarySettingsAcceptsAbsoluteOverridePathWithTrailingSlash() throws {
    let store = InMemoryCodexBinarySettingsStore()
    let settings = CodexBinarySettings(
        store: store,
        detector: StubCodexBinaryDetector(detectedURL: URL(filePath: "/usr/local/bin/codex"))
    )

    try settings.setOverridePath("/opt/homebrew/bin/codex/")

    #expect(store.overridePath == "/opt/homebrew/bin/codex")
    #expect(try settings.configuration().overrideBinaryURL == URL(filePath: "/opt/homebrew/bin/codex"))
}

@Test func codexBinarySettingsRejectsStoredRelativeOverridePathOnRead() throws {
    let settings = CodexBinarySettings(
        store: InMemoryCodexBinarySettingsStore(overridePath: "relative/codex"),
        detector: StubCodexBinaryDetector(detectedURL: URL(filePath: "/usr/local/bin/codex"))
    )

    #expect(throws: CodexBinarySettingsError.overrideMustBeAbsolute) {
        _ = try settings.configuration()
    }
}

private final class InMemoryCodexBinarySettingsStore: CodexBinarySettingsStoring, @unchecked Sendable {
    var overridePath: String?

    init(overridePath: String? = nil) {
        self.overridePath = overridePath
    }

    func codexBinaryOverridePath() -> String? {
        overridePath
    }

    func setCodexBinaryOverridePath(_ path: String?) {
        overridePath = path
    }
}

private struct StubCodexBinaryDetector: CodexBinaryDetecting {
    let detectedURL: URL?

    func detectedCodexBinaryURL() -> URL? {
        detectedURL
    }
}
