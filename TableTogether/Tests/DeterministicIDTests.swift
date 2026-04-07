import Testing
import Foundation
@testable import TableTogetherLib

@Suite("Deterministic ID Tests")
struct DeterministicIDTests {

    @Test("Same input produces same UUID")
    func sameInputProducesSameUUID() {
        let a = UUID.deterministic(from: "test:input")
        let b = UUID.deterministic(from: "test:input")
        #expect(a == b)
    }

    @Test("Different inputs produce different UUIDs")
    func differentInputsProduceDifferentUUIDs() {
        let a = UUID.deterministic(from: "test:input1")
        let b = UUID.deterministic(from: "test:input2")
        #expect(a != b)
    }

    @Test("UUID is valid format")
    func uuidIsValidFormat() {
        let id = UUID.deterministic(from: "anything")
        // Round-trip through string representation
        let str = id.uuidString
        let parsed = UUID(uuidString: str)
        #expect(parsed == id)
    }

    @Test("Household defaultID is stable")
    func householdDefaultIDIsStable() {
        #expect(Household.defaultID.uuidString == "00000000-0000-0000-0000-000000000001")
    }

    @Test("User defaultMeID is stable")
    func userDefaultMeIDIsStable() {
        #expect(User.defaultMeID.uuidString == "00000000-0000-0000-0000-000000000002")
    }

    @Test("Household and User default IDs are different")
    func defaultIDsAreDifferent() {
        #expect(Household.defaultID != User.defaultMeID)
    }

    @Test("MealArchetype deterministic ID is stable for same type")
    func archetypeIDIsStableForSameType() {
        let a = MealArchetype.deterministicID(for: .quickWeeknight)
        let b = MealArchetype.deterministicID(for: .quickWeeknight)
        #expect(a == b)
    }

    @Test("MealArchetype deterministic IDs differ across types")
    func archetypeIDsDifferAcrossTypes() {
        let a = MealArchetype.deterministicID(for: .quickWeeknight)
        let b = MealArchetype.deterministicID(for: .comfort)
        #expect(a != b)
    }

    @Test("All archetype types have unique deterministic IDs")
    func allArchetypeIDsAreUnique() {
        let ids = ArchetypeType.allCases.map { MealArchetype.deterministicID(for: $0) }
        let unique = Set(ids)
        #expect(unique.count == ids.count)
    }
}
