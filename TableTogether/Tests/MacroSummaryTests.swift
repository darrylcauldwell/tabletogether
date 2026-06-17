import Testing
import Foundation
@testable import TableTogetherLib

@Suite("MacroSummary Tests")
struct MacroSummaryTests {

    // MARK: - divided(by:)

    @Test("divided(by:) with a non-zero divisor scales each value")
    func dividedByNonZeroScales() {
        let total = MacroSummary(calories: 800, protein: 40, carbs: 100, fat: 20)
        let perServing = total.divided(by: 4)

        #expect(perServing.calories == 200)
        #expect(perServing.protein == 10)
        #expect(perServing.carbs == 25)
        #expect(perServing.fat == 5)
    }

    @Test("divided(by: 0) returns .empty with nil fields, not the original total")
    func dividedByZeroReturnsEmpty() {
        let total = MacroSummary(calories: 800, protein: 40, carbs: 100, fat: 20)
        let result = total.divided(by: 0)

        // Pins the fix: a zero divisor must surface bad input as empty,
        // never silently report the undivided total as a per-serving value.
        #expect(result == .empty)
        #expect(result.isEmpty)
        #expect(result.calories == nil)
        #expect(result.protein == nil)
        #expect(result.carbs == nil)
        #expect(result.fat == nil)
        // Explicitly NOT the original total.
        #expect(result != total)
    }

    @Test("/ operator delegates to divided(by:), including the zero-divisor guard")
    func divideOperatorMatchesDivided() {
        let total = MacroSummary(calories: 800, protein: 40, carbs: 100, fat: 20)
        #expect((total / 2) == total.divided(by: 2))
        #expect((total / 0) == .empty)
    }

    // MARK: - scaled(by:)

    @Test("scaled(by:) multiplies each present value and leaves nil as nil")
    func scaledByMultiplies() {
        let base = MacroSummary(calories: 100, protein: 10, carbs: nil, fat: 5)
        let scaled = base.scaled(by: 2.5)

        #expect(scaled.calories == 250)
        #expect(scaled.protein == 25)
        #expect(scaled.carbs == nil) // nil stays nil under scaling
        #expect(scaled.fat == 12.5)
    }

    // MARK: - addOptional / + semantics

    @Test("Adding treats nil as zero when the other value exists")
    func addingNilTreatedAsZeroWhenOtherExists() {
        let a = MacroSummary(calories: 100, protein: nil, carbs: 30, fat: nil)
        let b = MacroSummary(calories: 50, protein: 20, carbs: nil, fat: 8)
        let sum = a + b

        #expect(sum.calories == 150) // 100 + 50
        #expect(sum.protein == 20)   // nil + 20 → 20
        #expect(sum.carbs == 30)     // 30 + nil → 30
        #expect(sum.fat == 8)        // nil + 8  → 8
    }

    @Test("Adding nil to nil stays nil")
    func addingNilPlusNilStaysNil() {
        let a = MacroSummary(calories: nil, protein: 10, carbs: nil, fat: nil)
        let b = MacroSummary(calories: nil, protein: 5, carbs: nil, fat: nil)
        let sum = a + b

        #expect(sum.calories == nil) // nil + nil → nil
        #expect(sum.protein == 15)   // 10 + 5
        #expect(sum.carbs == nil)    // nil + nil → nil
        #expect(sum.fat == nil)      // nil + nil → nil
    }

    @Test("+ operator matches adding(_:)")
    func plusOperatorMatchesAdding() {
        let a = MacroSummary(calories: 100, protein: 10, carbs: 20, fat: 5)
        let b = MacroSummary(calories: 200, protein: 5, carbs: 10, fat: 2)
        #expect((a + b) == a.adding(b))
    }

    // MARK: - .zero vs .empty distinction

    @Test(".zero has explicit zero values; .empty has nil values — they are distinct")
    func zeroVsEmptyDistinction() {
        #expect(MacroSummary.empty.isEmpty)
        #expect(!MacroSummary.zero.isEmpty)

        #expect(MacroSummary.zero.calories == 0)
        #expect(MacroSummary.zero.protein == 0)
        #expect(MacroSummary.zero.carbs == 0)
        #expect(MacroSummary.zero.fat == 0)

        #expect(MacroSummary.empty.calories == nil)

        // Equatable must distinguish 0 from nil.
        #expect(MacroSummary.zero != MacroSummary.empty)
    }

    @Test(".zero is an additive identity for present values")
    func zeroIsAdditiveIdentity() {
        let macros = MacroSummary(calories: 300, protein: 25, carbs: 40, fat: 12)
        let sum = MacroSummary.zero + macros

        #expect(sum.calories == 300)
        #expect(sum.protein == 25)
        #expect(sum.carbs == 40)
        #expect(sum.fat == 12)
    }
}
