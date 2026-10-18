import Foundation

/// Semantic version (`1.2.3`, `v1.2.3-beta.1`). Comparison follows semver.org: a pre-release is lower than its release,
/// numeric identifiers compare as numbers, build metadata is ignored.
struct SemVer: Equatable, Comparable, Sendable, CustomStringConvertible {
    var major: Int
    var minor: Int
    var patch: Int
    var prerelease: [String]

    init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("v") || value.hasPrefix("V") { value.removeFirst() }
        if let plus = value.firstIndex(of: "+") { value = String(value[..<plus]) }
        var pre: [String] = []
        if let dash = value.firstIndex(of: "-") {
            pre = value[value.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            value = String(value[..<dash])
            if pre.contains(where: \.isEmpty) { return nil }
        }
        let numbers = value.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard numbers.count == 3, let major = numbers[0], let minor = numbers[1], let patch = numbers[2],
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = pre
    }

    static let zero = SemVer(major: 0, minor: 0, patch: 0, prerelease: [])

    private init(major: Int, minor: Int, patch: Int, prerelease: [String]) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    var isPrerelease: Bool { !prerelease.isEmpty }

    var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?): return leftNumber < rightNumber
            case (_?, nil): return true // numeric identifiers rank below alphanumeric ones
            case (nil, _?): return false
            default: return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
