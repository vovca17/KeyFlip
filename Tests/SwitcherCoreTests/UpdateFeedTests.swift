import XCTest
@testable import SwitcherCore

final class UpdateFeedTests: XCTestCase {
    private func release(_ tag: String, arch: String = "arm64", draft: Bool = false, url: String? = nil) -> GitHubRelease {
        let name = "KeyFlip-\(tag.dropFirst())-macOS-\(arch).zip"
        return GitHubRelease(tag_name: tag, draft: draft, prerelease: true,
            assets: [ReleaseAsset(name: name, size: 1024, browser_download_url: url ?? "https://github.com/vovca17/KeyFlip/releases/download/\(tag)/\(name)", digest: nil)])
    }
    func testVersionOrderingAndNoDowngrade() {
        XCTAssertTrue(UpdateFeed.newer("v0.10.0", than: "0.9.9"))
        XCTAssertFalse(UpdateFeed.newer("v0.5.2", than: "0.5.2"))
        XCTAssertFalse(UpdateFeed.newer("v0.5.1", than: "0.5.2"))
        XCTAssertNil(UpdateFeed.version("v0.5.2-beta"))
        XCTAssertNil(UpdateFeed.version("0.-1.2"))
        XCTAssertNil(UpdateFeed.version("0.5"))
    }
    func testSelectionMatchesArchitectureAndSkipsDrafts() {
        let items = [release("v0.5.2"), release("v0.5.3", arch: "x86_64"), release("v0.5.4", draft: true), release("v0.5.1")]
        XCTAssertEqual(UpdateFeed.select(items, current: "0.5.1", architecture: "arm64")?.tag_name, "v0.5.2")
        XCTAssertNil(UpdateFeed.select(items, current: "0.5.2", architecture: "arm64"))
        XCTAssertEqual(UpdateFeed.select(items, current: "0.5.1", architecture: "x86_64")?.tag_name, "v0.5.3")
    }
    func testForeignAndInsecureAssetURLsRejected() {
        for url in ["https://example.com/update.zip", "http://github.com/vovca17/KeyFlip/releases/download/v0.5.2/KeyFlip-0.5.2-macOS-arm64.zip", "https://github.com/other/KeyFlip/releases/download/v0.5.2/KeyFlip-0.5.2-macOS-arm64.zip"] {
            XCTAssertNil(UpdateFeed.archive(in: release("v0.5.2", url: url), architecture: "arm64"))
        }
    }
    func testArchiveRejectsTraversalAndUnexpectedRoots() {
        XCTAssertTrue(UpdateFeed.safeArchivePaths("KeyFlip.app/\nKeyFlip.app/Contents/MacOS/KeyboardSwitcher\n"))
        for paths in ["", "/tmp/file", "KeyFlip.app/../../file", "Other.app/Contents/file", "KeyFlip.app/Contents/../file", "KeyFlip.app/Contents\\file"] {
            XCTAssertFalse(UpdateFeed.safeArchivePaths(paths))
        }
    }
}
