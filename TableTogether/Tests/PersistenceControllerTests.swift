import Testing
import CloudKit
import CoreData
@testable import TableTogetherLib

@MainActor
struct PersistenceControllerTests {

    private func makeController() -> PersistenceController {
        PersistenceController(inMemory: true)
    }

    // MARK: - isStaleZoneError

    @Test("nil error is not a stale-zone error")
    func nilIsNotStale() {
        #expect(makeController().isStaleZoneError(nil) == false)
    }

    @Test("Direct zoneNotFound and unknownItem are stale-zone errors")
    func directZoneErrorsAreStale() {
        let controller = makeController()
        #expect(controller.isStaleZoneError(CKError(.zoneNotFound)) == true)
        #expect(controller.isStaleZoneError(CKError(.unknownItem)) == true)
    }

    @Test("An unrelated CKError is not a stale-zone error")
    func unrelatedErrorNotStale() {
        #expect(makeController().isStaleZoneError(CKError(.networkUnavailable)) == false)
    }

    @Test("partialFailure containing a zoneNotFound is stale")
    func partialWithZoneNotFoundIsStale() {
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["zone-a": CKError(.zoneNotFound)]]
        )
        #expect(makeController().isStaleZoneError(partial) == true)
    }

    @Test("partialFailure without any zone error is not stale")
    func partialWithoutZoneErrorNotStale() {
        let partial = NSError(
            domain: CKError.errorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["item": CKError(.networkFailure)]]
        )
        #expect(makeController().isStaleZoneError(partial) == false)
    }

    @Test("A nested underlying zoneNotFound is detected")
    func underlyingZoneNotFoundIsStale() {
        let wrapper = NSError(
            domain: "CustomDomain",
            code: 1,
            userInfo: [NSUnderlyingErrorKey: CKError(.zoneNotFound)]
        )
        #expect(makeController().isStaleZoneError(wrapper) == true)
    }

    // MARK: - participantID fallback

    @Test("participantID prefers the record name")
    func participantIDPrefersRecordName() {
        let id = PersistenceController.participantID(
            recordName: "rec-123", email: "a@b.com", phone: "555", index: 0)
        #expect(id == "rec-123")
    }

    @Test("participantID falls back to email, then phone, then index")
    func participantIDFallbackChain() {
        #expect(PersistenceController.participantID(recordName: nil, email: "a@b.com", phone: "555", index: 2) == "a@b.com")
        #expect(PersistenceController.participantID(recordName: nil, email: nil, phone: "555", index: 2) == "555")
        #expect(PersistenceController.participantID(recordName: nil, email: nil, phone: nil, index: 2) == "pending-2")
    }

    @Test("Two all-nil pending participants get distinct positional IDs")
    func pendingParticipantsAreDistinct() {
        let a = PersistenceController.participantID(recordName: nil, email: nil, phone: nil, index: 0)
        let b = PersistenceController.participantID(recordName: nil, email: nil, phone: nil, index: 1)
        #expect(a != b)
    }
}
