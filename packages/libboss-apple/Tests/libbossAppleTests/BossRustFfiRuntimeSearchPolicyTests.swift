import XCTest

@testable import libbossApple

final class BossRustFfiRuntimeSearchPolicyTests: XCTestCase {
    func testExplicitLibraryPathPrefersPrimaryEnvVar() {
        let path = BossRustFfiRuntimeSearchPolicy.explicitLibraryPath(environment: [
            BossRustFfiRuntimeSearchPolicy.explicitDylibEnvVar: "/tmp/primary.dylib",
            BossRustFfiRuntimeSearchPolicy.legacyExplicitDylibEnvVar: "/tmp/legacy.dylib",
        ])

        XCTAssertEqual(path, "/tmp/primary.dylib")
    }

    func testExplicitLibraryPathFallsBackToLegacyEnvVar() {
        let path = BossRustFfiRuntimeSearchPolicy.explicitLibraryPath(environment: [
            BossRustFfiRuntimeSearchPolicy.legacyExplicitDylibEnvVar: "/tmp/legacy.dylib",
        ])

        XCTAssertEqual(path, "/tmp/legacy.dylib")
    }

    func testExplicitLibraryPathIgnoresBlankValues() {
        let path = BossRustFfiRuntimeSearchPolicy.explicitLibraryPath(environment: [
            BossRustFfiRuntimeSearchPolicy.explicitDylibEnvVar: "   ",
        ])

        XCTAssertNil(path)
    }

    func testExplicitHomebrewLibraryPathBuildsDylibPathFromPrefix() {
        let path = BossRustFfiRuntimeSearchPolicy.explicitHomebrewLibraryPath(environment: [
            BossRustFfiRuntimeSearchPolicy.explicitHomebrewPrefixEnvVar: "/opt/homebrew/opt/libboss-ffi",
        ])

        XCTAssertEqual(path, "/opt/homebrew/opt/libboss-ffi/lib/libboss_ffi.dylib")
    }

    func testExplicitHomebrewLibraryPathIgnoresBlankValues() {
        let path = BossRustFfiRuntimeSearchPolicy.explicitHomebrewLibraryPath(environment: [
            BossRustFfiRuntimeSearchPolicy.explicitHomebrewPrefixEnvVar: "   ",
        ])

        XCTAssertNil(path)
    }

    func testRepositorySearchEnvVarCanDisableDebugFallback() {
        let allowed = BossRustFfiRuntimeSearchPolicy.allowsRepositorySearch(environment: [
            BossRustFfiRuntimeSearchPolicy.allowRepositorySearchEnvVar: "0",
        ])

        XCTAssertFalse(allowed)
    }

    func testRepositorySearchEnvVarRecognizesTruthyValues() {
        let allowed = BossRustFfiRuntimeSearchPolicy.allowsRepositorySearch(environment: [
            BossRustFfiRuntimeSearchPolicy.allowRepositorySearchEnvVar: "true",
        ])

        XCTAssertTrue(allowed)
    }

    func testRepositoryChannelIsMarkedDevelopmentOnly() {
        XCTAssertTrue(BossRustFfiRuntimeChannel.repositoryDebugFallback.isDevelopmentOnly)
        XCTAssertFalse(BossRustFfiRuntimeChannel.explicitDylib.isDevelopmentOnly)
        XCTAssertFalse(BossRustFfiRuntimeChannel.explicitHomebrewPrefix.isDevelopmentOnly)
    }
}
