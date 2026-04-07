import Testing
import Foundation
@testable import TableTogetherLib

@Suite("PendingInvitationStore Tests", .serialized)
struct PendingInvitationStoreTests {

    init() {
        PendingInvitationStore.clearAll()
    }

    @Test("Stores and retrieves a label")
    func storeAndRetrieve() {
        PendingInvitationStore.setLabel("Alice", forShareRecordName: "share-1")
        #expect(PendingInvitationStore.label(forShareRecordName: "share-1") == "Alice")
        PendingInvitationStore.clearAll()
    }

    @Test("Returns nil for unknown record")
    func nilForUnknown() {
        #expect(PendingInvitationStore.label(forShareRecordName: "missing") == nil)
    }

    @Test("Overwrites existing label")
    func overwritesExisting() {
        PendingInvitationStore.setLabel("Alice", forShareRecordName: "share-1")
        PendingInvitationStore.setLabel("Bob", forShareRecordName: "share-1")
        #expect(PendingInvitationStore.label(forShareRecordName: "share-1") == "Bob")
        PendingInvitationStore.clearAll()
    }

    @Test("Removes a label")
    func removesLabel() {
        PendingInvitationStore.setLabel("Alice", forShareRecordName: "share-1")
        PendingInvitationStore.removeLabel(forShareRecordName: "share-1")
        #expect(PendingInvitationStore.label(forShareRecordName: "share-1") == nil)
    }

    @Test("Multiple labels coexist")
    func multipleLabels() {
        PendingInvitationStore.setLabel("Alice", forShareRecordName: "share-1")
        PendingInvitationStore.setLabel("Bob", forShareRecordName: "share-2")
        #expect(PendingInvitationStore.label(forShareRecordName: "share-1") == "Alice")
        #expect(PendingInvitationStore.label(forShareRecordName: "share-2") == "Bob")
        PendingInvitationStore.clearAll()
    }

    @Test("clearAll removes everything")
    func clearAllRemoves() {
        PendingInvitationStore.setLabel("Alice", forShareRecordName: "share-1")
        PendingInvitationStore.setLabel("Bob", forShareRecordName: "share-2")
        PendingInvitationStore.clearAll()
        #expect(PendingInvitationStore.label(forShareRecordName: "share-1") == nil)
        #expect(PendingInvitationStore.label(forShareRecordName: "share-2") == nil)
    }
}
