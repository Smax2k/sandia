import XCTest
@testable import SandiaCore

/// The reference policy is pure: these tests need no display and never call
/// CoreGraphics.
final class GammaReferencePolicyTests: XCTestCase {
    private let key = "display-uuid"
    private let baseline = GammaTable(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])
    private let tint = GammaTable(red: [0, 0.25, 0.795329], green: [0, 0.5, 1], blue: [0, 0.5, 1])
    private let otherRead = GammaTable(red: [0, 0.4, 0.9], green: [0, 0.5, 1], blue: [0, 0.5, 1])

    // MARK: - Reconfiguration and replug

    func testKnownReferenceIsKeptForTheSameKey() {
        var policy = GammaReferencePolicy()
        XCTAssertEqual(policy.reference(for: key, read: baseline), .adopted(baseline))
        // A reconfiguration re-reads the display: the known reference wins.
        XCTAssertEqual(policy.reference(for: key, read: otherRead), .known(baseline))
        XCTAssertEqual(policy.reference(for: key), baseline)
    }

    func testReplugAfterOurTintKeepsTheKnownReference() {
        var policy = GammaReferencePolicy()
        _ = policy.reference(for: key, read: baseline)
        policy.recordWrite(tint, for: key, succeeded: true)
        // The display comes back still carrying the tint; it must not replace
        // the reference captured before it.
        XCTAssertEqual(policy.reference(for: key, read: tint), .known(baseline))
        XCTAssertEqual(policy.reference(for: key), baseline)
    }

    // MARK: - Own tint is not a baseline

    func testOwnTintIsRejectedWhenNoReferenceIsKnown() {
        var policy = GammaReferencePolicy()
        policy.recordWrite(tint, for: key, succeeded: true)
        XCTAssertEqual(policy.reference(for: key, read: tint), .rejectedOwnTint)
        XCTAssertNil(policy.reference(for: key))
    }

    func testDifferentReadIsAcceptedWhenNoReferenceIsKnown() {
        var policy = GammaReferencePolicy()
        policy.recordWrite(tint, for: key, succeeded: true)
        XCTAssertEqual(policy.reference(for: key, read: otherRead), .adopted(otherRead))
    }

    // MARK: - Write results

    func testFailedWriteLeavesTheInstalledTableUntouched() {
        var policy = GammaReferencePolicy()
        policy.recordWrite(tint, for: key, succeeded: true)
        policy.recordWrite(otherRead, for: key, succeeded: false)

        XCTAssertEqual(policy.installedTable(for: key), tint)
        XCTAssertEqual(policy.reference(for: key, read: tint), .rejectedOwnTint)
        XCTAssertEqual(policy.reference(for: key, read: otherRead), .adopted(otherRead))
    }

    func testNoOpWriteDoesNotCountAsATint() {
        var policy = GammaReferencePolicy()
        _ = policy.reference(for: key, read: baseline)
        policy.recordWrite(baseline, for: key, succeeded: true)
        XCTAssertNil(policy.installedTable(for: key))
        // The baseline read is still acceptable as a reference.
        XCTAssertEqual(policy.reference(for: key, read: baseline), .known(baseline))
    }

    // MARK: - Restore

    func testRestoreThatLeavesTheTintIsNotABaseline() {
        var policy = GammaReferencePolicy()
        policy.recordWrite(tint, for: key, succeeded: true)
        XCTAssertEqual(policy.recordRestore(read: tint, for: key), .stillOwnTint)
        XCTAssertNil(policy.reference(for: key))
        XCTAssertEqual(policy.installedTable(for: key), tint)
    }

    func testRestoreThatClearsTheTintAdoptsTheReadAsReference() {
        var policy = GammaReferencePolicy()
        policy.recordWrite(tint, for: key, succeeded: true)
        XCTAssertEqual(policy.recordRestore(read: baseline, for: key), .adoptedReference(baseline))
        XCTAssertNil(policy.installedTable(for: key))
        XCTAssertEqual(policy.reference(for: key), baseline)
    }

    func testRestoreThatClearsTheTintKeepsAKnownReference() {
        var policy = GammaReferencePolicy()
        _ = policy.reference(for: key, read: baseline)
        policy.recordWrite(tint, for: key, succeeded: true)
        XCTAssertEqual(policy.recordRestore(read: otherRead, for: key), .cleared)
        XCTAssertEqual(policy.reference(for: key), baseline)
    }

    // MARK: - Table comparison

    func testTableComparisonToleratesStorageRoundingOnly() {
        XCTAssertTrue(baseline.isClose(to: baseline))
        var rounded = baseline
        rounded.red[2] += 0.0005
        XCTAssertTrue(baseline.isClose(to: rounded))
        rounded.red[2] += 0.01
        XCTAssertFalse(baseline.isClose(to: rounded))
    }

    func testTablesOfDifferentLengthsNeverMatch() {
        let shorter = GammaTable(red: [0, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])
        XCTAssertFalse(baseline.isClose(to: shorter))
    }
}
