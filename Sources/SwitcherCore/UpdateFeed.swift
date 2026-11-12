import Foundation

public struct ReleaseAsset: Decodable, Sendable {
    public let name: String
    public let size: Int
    public let browser_download_url: String
    public let digest: String?
}
public struct GitHubRelease: Decodable, Sendable {
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [ReleaseAsset]
}
public enum UpdateFeed {
    public static func version(_ tag: String) -> [Int]? {
        let raw = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 ? numbers : nil
    }
    public static func newer(_ lhs: String, than rhs: String) -> Bool {
        guard let left = version(lhs), let right = version(rhs) else { return false }
        return right.lexicographicallyPrecedes(left)
    }
    public static func archive(in release: GitHubRelease, architecture: String) -> ReleaseAsset? {
        guard !release.draft, version(release.tag_name) != nil else { return nil }
        let names = ["KeyFlip-\(release.tag_name.dropFirst(release.tag_name.hasPrefix("v") ? 1 : 0))-macOS-universal.zip",
                     "KeyFlip-\(release.tag_name.dropFirst(release.tag_name.hasPrefix("v") ? 1 : 0))-macOS-\(architecture).zip"]
        return names.compactMap { name in release.assets.first { asset in
            guard asset.name == name, asset.size > 0, asset.size <= 200_000_000,
                  let url = URL(string: asset.browser_download_url) else { return false }
            return url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil &&
                url.path == "/vovca17/KeyFlip/releases/download/\(release.tag_name)/\(name)" && url.query == nil
        }}.first
    }
    public static func select(_ releases: [GitHubRelease], current: String, architecture: String) -> GitHubRelease? {
        releases.filter { newer($0.tag_name, than: current) && archive(in: $0, architecture: architecture) != nil }
            .sorted { newer($0.tag_name, than: $1.tag_name) }.first
    }
    public static func safeArchivePaths(_ listing: String) -> Bool {
        let paths = listing.split(separator: "\n")
        return !paths.isEmpty && paths.allSatisfy { path in
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            return parts.first == "KeyFlip.app" && !parts.contains("..") && !parts.contains(".") && !path.contains("\\")
        }
    }
}
