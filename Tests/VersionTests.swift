import Foundation
@main struct VersionTests {
    static func main() {
        let cases = [("0.2.0", "0.2.1"), ("0.9.9", "0.10.0"), ("0.99.0", "1.0.0"), ("v0.2.0", "v0.3.0")]
        for (a, b) in cases { precondition(ReleaseVersion(a)! < ReleaseVersion(b)!) }
        precondition(ReleaseVersion("v0.2.0") == ReleaseVersion("0.2.0"))
        for bad in ["", "0.2", "1.x.0", "1.2.3.4", "-1.0.0", "1.0.0-beta", "1..0"] { precondition(ReleaseVersion(bad) == nil) }
        print("PASS: 12 release version checks")
    }
}
