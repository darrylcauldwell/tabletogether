import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
struct UserIdentityTests {

    private func makeContext() -> NSManagedObjectContext {
        PersistenceController(inMemory: true).container.viewContext
    }

    private func makeUser(in context: NSManagedObjectContext, id: UUID, name: String = "Me") -> User {
        User(context: context, id: id, displayName: name)
    }

    // MARK: - deterministicID

    @Test func sameRecordNameYieldsSameID() {
        let a = UserIdentity.deterministicID(fromRecordName: "_abc123")
        let b = UserIdentity.deterministicID(fromRecordName: "_abc123")
        #expect(a == b)
    }

    @Test func differentRecordNamesYieldDifferentIDs() {
        let a = UserIdentity.deterministicID(fromRecordName: "_owner")
        let b = UserIdentity.deterministicID(fromRecordName: "_participant")
        #expect(a != b)
    }

    @Test func derivedIDHasRFC4122VariantBits() {
        let id = UserIdentity.deterministicID(fromRecordName: "_abc123")
        let bytes = id.uuid
        #expect(bytes.6 & 0xF0 == 0x50)
        #expect(bytes.8 & 0xC0 == 0x80)
    }

    @Test func derivedIDNeverCollidesWithProvisionalID() {
        let id = UserIdentity.deterministicID(fromRecordName: "_abc123")
        #expect(id != User.defaultMeID)
    }

    // MARK: - chooseMyRow

    @Test func singleCandidateIsChosen() {
        let context = makeContext()
        let user = makeUser(in: context, id: User.defaultMeID)
        let chosen = UserIdentity.chooseMyRow(from: [(user: user, isInPrivateStore: false)])
        #expect(chosen === user)
    }

    @Test func lonePrivateStoreRowWinsAmongSeveral() {
        let context = makeContext()
        let mine = makeUser(in: context, id: User.defaultMeID)
        let mirror = makeUser(in: context, id: User.defaultMeID)
        let chosen = UserIdentity.chooseMyRow(from: [
            (user: mirror, isInPrivateStore: false),
            (user: mine, isInPrivateStore: true)
        ])
        #expect(chosen === mine)
    }

    @Test func multipleIndistinguishableRowsAreNotClaimed() {
        let context = makeContext()
        let a = makeUser(in: context, id: User.defaultMeID)
        let b = makeUser(in: context, id: User.defaultMeID)
        #expect(UserIdentity.chooseMyRow(from: [
            (user: a, isInPrivateStore: false),
            (user: b, isInPrivateStore: false)
        ]) == nil)
        #expect(UserIdentity.chooseMyRow(from: [
            (user: a, isInPrivateStore: true),
            (user: b, isInPrivateStore: true)
        ]) == nil)
    }

    // MARK: - User.current resolution order

    @Test func resolvedIDIsPreferredOverProvisional() {
        let context = makeContext()
        let resolvedID = UserIdentity.deterministicID(fromRecordName: "_abc123")
        let provisional = makeUser(in: context, id: User.defaultMeID)
        let me = makeUser(in: context, id: resolvedID)
        let current = User.current(in: [provisional, me], resolvedID: resolvedID)
        #expect(current === me)
    }

    @Test func fallsBackToProvisionalWhenUnresolved() {
        let context = makeContext()
        let other = makeUser(in: context, id: UUID(), name: "Alice")
        let provisional = makeUser(in: context, id: User.defaultMeID)
        let current = User.current(in: [other, provisional], resolvedID: nil)
        #expect(current === provisional)
    }

    @Test func fallsBackToProvisionalWhenResolvedRowMissing() {
        let context = makeContext()
        let resolvedID = UserIdentity.deterministicID(fromRecordName: "_abc123")
        let provisional = makeUser(in: context, id: User.defaultMeID)
        let current = User.current(in: [provisional], resolvedID: resolvedID)
        #expect(current === provisional)
    }

    @Test func fallsBackToFirstUserWhenNoProvisionalExists() {
        let context = makeContext()
        let other = makeUser(in: context, id: UUID(), name: "Alice")
        let current = User.current(in: [other], resolvedID: nil)
        #expect(current === other)
    }
}
