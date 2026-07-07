import Testing
import Foundation
import CoreData
@testable import TableTogetherLib

@MainActor
@Suite("FoodItemImporter Tests", .serialized)
struct FoodItemImporterTests {

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let context = PersistenceController(inMemory: true).container.viewContext
        let household = Household(context: context, name: "Test Household")
        return (context, household)
    }

    private func sampleSingleJSON(displayName: String = "Chicken breast (raw)") -> Data {
        let json = """
        {
          "displayName": "\(displayName)",
          "dataType": "Foundation",
          "fdcId": 174616,
          "usdaDescription": "Chicken, broilers or fryers, breast, meat only, raw",
          "caloriesPer100g": 120,
          "proteinPer100g": 22.5,
          "carbsPer100g": 0,
          "fatPer100g": 2.6,
          "fiberPer100g": 0,
          "userAliases": ["chicken breast", "chicken fillet"]
        }
        """
        return Data(json.utf8)
    }

    private func sampleArrayJSON() -> Data {
        let json = """
        [
          {
            "displayName": "Brown rice (cooked)",
            "dataType": "Foundation",
            "caloriesPer100g": 123,
            "proteinPer100g": 2.7,
            "carbsPer100g": 25.6,
            "fatPer100g": 1.0
          },
          {
            "displayName": "Olive oil",
            "dataType": "Foundation",
            "caloriesPer100g": 884,
            "proteinPer100g": 0,
            "carbsPer100g": 0,
            "fatPer100g": 100,
            "userAliases": ["evoo", "extra virgin olive oil"]
          }
        ]
        """
        return Data(json.utf8)
    }

    private func foodItemCount(in context: NSManagedObjectContext) -> Int {
        let request = NSFetchRequest<FoodItem>(entityName: "FoodItem")
        return (try? context.count(for: request)) ?? 0
    }

    // MARK: - Decode

    @Test("Decodes a single food item")
    func decodesSingleFoodItem() throws {
        let importer = FoodItemImporter()
        let items = try importer.decode(data: sampleSingleJSON())
        #expect(items.count == 1)
        #expect(items[0].displayName == "Chicken breast (raw)")
        #expect(items[0].fdcId == 174616)
        #expect(items[0].caloriesPer100g == 120)
    }

    @Test("Decodes an array of food items")
    func decodesArrayFoodItems() throws {
        let importer = FoodItemImporter()
        let items = try importer.decode(data: sampleArrayJSON())
        #expect(items.count == 2)
        #expect(items.contains(where: { $0.displayName == "Brown rice (cooked)" }))
        #expect(items.contains(where: { $0.displayName == "Olive oil" }))
    }

    @Test("Decode failure throws decodingFailed")
    func decodeFailureThrows() {
        let importer = FoodItemImporter()
        let bad = Data("not json".utf8)
        #expect(throws: FoodItemImportError.self) {
            _ = try importer.decode(data: bad)
        }
    }

    // MARK: - Import

    @Test("Imports a single food item with all fields")
    func importSingleItem() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()
        let items = try importer.decode(data: sampleSingleJSON())
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 1)
        #expect(result.skipped == 0)
        #expect(result.errors.isEmpty)
        #expect(foodItemCount(in: context) == 1)

        let fetched = try context.fetch(NSFetchRequest<FoodItem>(entityName: "FoodItem"))
        let item = try #require(fetched.first)
        #expect(item.displayName == "Chicken breast (raw)")
        #expect(item.fdcId == 174616)
        #expect(item.caloriesPer100g == 120)
        #expect(item.proteinPer100g == 22.5)
        #expect(item.userAliasesList.count == 2)
        #expect(item.household === household)
        #expect(item.normalizedName == "chicken breast (raw)")
    }

    @Test("Imports an array of food items")
    func importArrayItems() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()
        let items = try importer.decode(data: sampleArrayJSON())
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 2)
        #expect(foodItemCount(in: context) == 2)
    }

    // MARK: - Dedup

    @Test("Re-importing the same fdcId is skipped")
    func dedupByFdcId() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        let items = try importer.decode(data: sampleSingleJSON())
        let first = importer.importDecoded(items, context: context, household: household)
        #expect(first.imported == 1)

        let second = importer.importDecoded(items, context: context, household: household)
        #expect(second.imported == 0)
        #expect(second.skipped == 1)
        #expect(foodItemCount(in: context) == 1)
    }

    @Test("Re-importing same name+brand without fdcId is skipped")
    func dedupByNameAndBrand() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        let json = """
        {
          "displayName": "Custom protein bar",
          "brandOwner": "MadeUpBrand",
          "caloriesPer100g": 400,
          "proteinPer100g": 30,
          "carbsPer100g": 35,
          "fatPer100g": 14
        }
        """
        let items = try importer.decode(data: Data(json.utf8))

        _ = importer.importDecoded(items, context: context, household: household)
        let second = importer.importDecoded(items, context: context, household: household)

        #expect(second.imported == 0)
        #expect(second.skipped == 1)
        #expect(foodItemCount(in: context) == 1)
    }

    @Test("Same name with different brand owners do not collide")
    func nameWithDifferentBrandsDoesNotCollide() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        let json = """
        [
          {"displayName": "Chicken breast", "brandOwner": "Tesco", "caloriesPer100g": 120, "proteinPer100g": 22, "carbsPer100g": 0, "fatPer100g": 2},
          {"displayName": "Chicken breast", "brandOwner": "Sainsburys", "caloriesPer100g": 121, "proteinPer100g": 23, "carbsPer100g": 0, "fatPer100g": 2}
        ]
        """
        let items = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 2)
        #expect(foodItemCount(in: context) == 2)
    }

    @Test("Same name with no brand and one with brand do not collide")
    func unbrandedAndBrandedDoNotCollide() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        let json = """
        [
          {"displayName": "Olive oil", "caloriesPer100g": 884, "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 100},
          {"displayName": "Olive oil", "brandOwner": "Filippo Berio", "caloriesPer100g": 884, "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 100}
        ]
        """
        let items = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 2)
    }

    @Test("Within-batch duplicates are deduped")
    func withinBatchDuplicates() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        // Same fdcId twice in one batch
        let json = """
        [
          {"displayName": "Chicken breast", "fdcId": 174616, "caloriesPer100g": 120, "proteinPer100g": 22, "carbsPer100g": 0, "fatPer100g": 2},
          {"displayName": "Chicken breast (different desc)", "fdcId": 174616, "caloriesPer100g": 121, "proteinPer100g": 23, "carbsPer100g": 0, "fatPer100g": 3}
        ]
        """
        let items = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 1)
        #expect(result.skipped == 1)
        #expect(foodItemCount(in: context) == 1)
    }

    // MARK: - Edge cases

    @Test("Items with empty displayName are reported as errors")
    func emptyDisplayNameIsError() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        let json = """
        [
          {"displayName": "", "caloriesPer100g": 100, "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 0},
          {"displayName": "Valid", "caloriesPer100g": 100, "proteinPer100g": 0, "carbsPer100g": 0, "fatPer100g": 0}
        ]
        """
        let items = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 1)
        #expect(result.errors.count == 1)
    }

    @Test("Defaults applied when optional fields are absent")
    func optionalFieldDefaults() throws {
        let (context, household) = makeContext()
        let importer = FoodItemImporter()

        // Minimum required: displayName + 4 macros
        let json = """
        {
          "displayName": "Bare item",
          "caloriesPer100g": 100,
          "proteinPer100g": 5,
          "carbsPer100g": 10,
          "fatPer100g": 3
        }
        """
        let items = try importer.decode(data: Data(json.utf8))
        let result = importer.importDecoded(items, context: context, household: household)

        #expect(result.imported == 1)
        let item = try #require(try context.fetch(NSFetchRequest<FoodItem>(entityName: "FoodItem")).first)
        #expect(item.dataType == "Custom")
        #expect(item.fdcId == 0)
        #expect(item.brandOwner == nil)
        #expect(item.fiberPer100g == nil)
        #expect(item.userAliasesList.isEmpty)
        #expect(item.usdaDescription == "Bare item") // falls back to displayName
    }

    // MARK: - Round-trip

    @Test("CodableFoodItem round-trips through Core Data")
    func codableRoundTrip() throws {
        let (context, _) = makeContext()
        let original = FoodItem(
            context: context,
            fdcId: 12345,
            usdaDescription: "Original description",
            displayName: "Round Trip Item",
            dataType: "Foundation",
            brandOwner: nil,
            caloriesPer100g: 200,
            proteinPer100g: 10,
            carbsPer100g: 20,
            fatPer100g: 5,
            fiberPer100g: 3,
            sugarPer100g: 8,
            sodiumMgPer100g: 150,
            userAliases: ["alias1", "alias2"]
        )

        let codable = CodableFoodItem(from: original)
        #expect(codable.displayName == "Round Trip Item")
        #expect(codable.fdcId == 12345)
        #expect(codable.proteinPer100g == 10)
        #expect(codable.fiberPer100g == 3)
        #expect(codable.userAliases?.count == 2)
    }

    @Test("A barcode-sized fdcId maps to the 0 sentinel instead of trapping")
    func barcodeSizedFdcIdDoesNotTrap() {
        // Open Food Facts maps product barcodes into fdcId; an EAN-13
        // (13 digits) exceeds Int32.max and used to crash the app in
        // FoodItem.init / IngredientResolverService.createFoodItem.
        let (context, household) = makeContext()
        let item = FoodItem(
            context: context,
            fdcId: 5_000_169_005_535,
            usdaDescription: "Barcode product",
            displayName: "Barcode product",
            dataType: "Branded",
            caloriesPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 1,
            fatPer100g: 1
        )
        item.household = household
        #expect(item.fdcId == 0)
    }
}
