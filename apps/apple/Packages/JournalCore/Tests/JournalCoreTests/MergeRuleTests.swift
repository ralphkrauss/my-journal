import XCTest

@testable import JournalCore

/// The template rules and the cases where merging must keep content it doesn't import as a record
/// (docs/design/join-with-local-journals.md §2.1–2.4).
extension MergeTests {
    private func template(_ title: String, _ text: String, deleted: Bool = false) -> JournalItem {
        var item = JournalItem(kind: "template", title: title, document: .plain(text))
        if deleted { item.deletedAt = Date() }
        return item
    }
    private func imageBlock(_ id: UUID) -> DocumentBlock {
        DocumentBlock(kind: "image", attachmentID: id, imageDescription: "Photo", mediaType: "image/png")
    }

    func testTemplateRulesFromTheDesign() async throws {
        let server = MergeServer()
        let (mac, macSync) = try await otherDevice(server)
        var macGratitude = fresh(try XCTUnwrap(BuiltInTemplates.all.first { $0.title == "Gratitude" }))
        macGratitude.document = .plain("Edited on the Mac")
        let macRecipe = template("Recipe", "Ingredients")
        let macRetro = template("Retro", "What went well")
        for item in [macGratitude, macRecipe, macRetro, template("Standup", "A"), template("Standup", "B")] {
            try await mac.save(item)
        }
        try await macSync.synchronize()

        let local = try store(key: deviceKey)
        let unedited = fresh(try XCTUnwrap(BuiltInTemplates.all.first { $0.title == "Gratitude" }))
        let dailyReflection = fresh(try XCTUnwrap(BuiltInTemplates.all.first { $0.title == "Daily Reflection" }))
        let image = Data(repeating: 3, count: 1024)
        let imageID = try await local.addAttachment(image)
        var recipe = template("Recipe", "")
        recipe.document = .init(blocks: [DocumentBlock(runs: [TextRun("With a photo")]), imageBlock(imageID)])
        let standup = template("Standup", "C")
        let deletedRetro = template("Retro", "Old version", deleted: true)
        var travel = JournalItem(kind: "journal", title: "Travel")
        travel.defaultTemplateID = recipe.id
        var notes = JournalItem(kind: "journal", title: "Notes")
        notes.defaultTemplateID = dailyReflection.id
        var ideas = JournalItem(kind: "journal", title: "Ideas")
        ideas.defaultTemplateID = standup.id
        for item in [unedited, dailyReflection, recipe, standup, deletedRetro, travel, notes, ideas] {
            try await local.save(item)
        }

        let (staged, engine) = try await merge(local, into: server)
        let result = try await downloaded(server).items()
        XCTAssertEqual(
            live(result, "template", "Gratitude").map(\.document), [macGratitude.document],
            "An unedited built-in is left out even when the server's copy was edited, and isn't reviewed.")
        XCTAssertEqual(live(result, "template", "Daily Reflection").count, 0)
        XCTAssertEqual(live(result, "template", "Standup").count, 3, "With several of a name, each is added.")
        XCTAssertEqual(live(result, "template", "Retro").map(\.id), [macRetro.id])
        XCTAssertEqual(
            result.filter { $0.title == "Retro" && $0.deletedAt != nil }.count, 1,
            "A template in Recently Deleted is imported as it is, without matching.")
        func journal(_ title: String) throws -> JournalItem { try XCTUnwrap(result.first { $0.title == title }) }
        XCTAssertEqual(try journal("Travel").defaultTemplateID, macRecipe.id, "It follows the reviewed template.")
        XCTAssertNil(try journal("Notes").defaultTemplateID, "An unmatched built-in isn't on the server.")
        let addedStandup = try XCTUnwrap(
            live(result, "template", "Standup").first { $0.document == standup.document })
        XCTAssertEqual(try journal("Ideas").defaultTemplateID, addedStandup.id)

        // The reviewed template's image is staged; keeping this device's version sends it with its image.
        let pendingReviews = try await staged.conflicts()
        let review = try XCTUnwrap(pendingReviews.first)
        XCTAssertEqual(review.id, macRecipe.id)
        let mergedImage = try XCTUnwrap(review.local.document.attachmentIDs.first)
        try await staged.resolve(review, choice: .local)
        try await engine.synchronize()
        let uploaded = await server.images[mergedImage]
        XCTAssertNotNil(uploaded)
        let resolved = try await downloaded(server)
        let keptRecipe = try await resolved.item(macRecipe.id)
        XCTAssertEqual(keptRecipe?.document.attachmentIDs, [mergedImage])
        let keptImage = try await resolved.attachment(mergedImage)
        XCTAssertEqual(keptImage, image)
    }

    func testEditsAfterAnInterruptedAttemptAreOrdinaryEdits() async throws {
        let server = MergeServer()
        let local = try store(key: deviceKey)
        var ideas = template("Ideas", "First")
        var travel = JournalItem(kind: "journal", title: "Travel")
        try await local.save(ideas)
        try await local.save(travel)
        // The first attempt sent everything but wasn't committed.
        try await merge(local, into: server)
        let storedIdeas = try await local.item(ideas.id)
        ideas = try XCTUnwrap(storedIdeas)
        ideas.document = .plain("Second")
        try await local.save(ideas)
        let storedTravel = try await local.item(travel.id)
        travel = try XCTUnwrap(storedTravel)
        travel.title = "Trips"
        try await local.save(travel)

        let (staged, _) = try await merge(local, into: server)
        let reviews = try await staged.conflicts()
        XCTAssertTrue(reviews.isEmpty, "What only this device wrote isn't reviewed against itself.")
        let result = try await downloaded(server).items()
        XCTAssertEqual(live(result, "template", "Ideas").map(\.document), [ideas.document])
        XCTAssertEqual(result.filter { $0.kind == "journal" }.map(\.title), ["Trips"])
    }

    func testAMissingImageDoesNotStopTheMerge() async throws {
        let server = MergeServer()
        let local = try store(key: deviceKey)
        let journal = JournalItem(kind: "journal", title: "Photos")
        let imageID = try await local.addAttachment(Data(repeating: 5, count: 512))
        let entry = JournalItem(
            kind: "entry", journalID: journal.id, title: "Beach",
            document: .init(blocks: [DocumentBlock(runs: [TextRun("Sunset")]), imageBlock(imageID)]))
        try await local.save(journal)
        try await local.save(entry)
        let folder = await local.directory.appendingPathComponent("attachments/\(imageID.uuidString.lowercased())")
        try FileManager.default.removeItem(at: folder)

        let (staged, _) = try await merge(local, into: server)
        let result = try await downloaded(server).items()
        XCTAssertEqual(result.filter { $0.title == "Beach" }.count, 1, "The entry is merged without its image.")
        let unsent = try await staged.pending()
        XCTAssertTrue(unsent.isEmpty)
        let images = await server.images
        XCTAssertTrue(images.isEmpty)
    }

    func testAnImageThatCantBeReadFailsTheMergeInsteadOfBeingLost() async throws {
        let server = MergeServer()
        let local = try store(key: deviceKey)
        let journal = JournalItem(kind: "journal", title: "Photos")
        let imageID = try await local.addAttachment(Data(repeating: 5, count: 512))
        try await local.save(journal)
        try await local.save(
            JournalItem(
                kind: "entry", journalID: journal.id, title: "Beach",
                document: .init(blocks: [DocumentBlock(runs: [TextRun("Sunset")]), imageBlock(imageID)])))
        let file = await local.directory.appendingPathComponent("attachments/\(imageID.uuidString.lowercased())")
        try Data(repeating: 0, count: 512).write(to: file)
        do {
            try await merge(local, into: server)
            XCTFail("An image that can't be decrypted must not be dropped.")
        } catch {}
        let records = await server.records
        XCTAssertTrue(records.isEmpty, "Nothing was sent; the merge can be tried again.")
    }

    func testATemplateThatDiffersOnlyInParagraphsIsReviewedNotSkipped() async throws {
        let server = MergeServer()
        let (mac, macSync) = try await otherDevice(server)
        let serverPlan = JournalItem(kind: "template", title: "Plan", document: JournalDocument(markdown: "One\nTwo"))
        try await mac.save(serverPlan)
        try await macSync.synchronize()
        let local = try store(key: deviceKey)
        let localPlan = JournalItem(kind: "template", title: "Plan", document: JournalDocument(markdown: "One\n\nTwo"))
        try await local.save(localPlan)

        let (staged, _) = try await merge(local, into: server)
        let reviews = try await staged.conflicts()
        XCTAssertEqual(reviews.map(\.id), [serverPlan.id])
        XCTAssertEqual(reviews.first?.local.document.markdown, localPlan.document.markdown)
    }

    func testVersionsOfWhatIsntImportedAreKept() async throws {
        let server = MergeServer()
        let (mac, macSync) = try await otherDevice(server)
        let serverDefault = JournalItem(kind: "journal", title: "Default")
        try await mac.save(serverDefault)
        try await macSync.synchronize()

        let local = try store(key: deviceKey)
        let journal = JournalItem(kind: "journal", title: "Default")
        try await local.save(journal)
        var renamed = journal
        renamed.title = "Default on the iPad"
        try await local.recordConflict(
            RemoteChange(
                cursor: 1, recordId: journal.id, revision: 1, kind: "journal", payload: try await local.encode(renamed),
                deviceId: UUID(), modifiedAt: Date()))
        let builtIn = fresh(try XCTUnwrap(BuiltInTemplates.all.first { $0.title == "Gratitude" }))
        try await local.save(builtIn)
        var edited = builtIn
        edited.document = .plain("Edited elsewhere")
        try await local.recordConflict(
            RemoteChange(
                cursor: 2, recordId: builtIn.id, revision: 1, kind: "template", payload: try await local.encode(edited),
                deviceId: UUID(), modifiedAt: Date()))

        let (staged, _) = try await merge(local, into: server)
        let journalVersions = try await staged.history(for: serverDefault.id)
        XCTAssertTrue(
            journalVersions.contains { $0.title == "Default on the iPad" },
            "A combined journal's version awaiting review is kept in the server journal's Version History.")
        let reviews = try await staged.conflicts()
        XCTAssertEqual(
            reviews.map(\.remote.document), [edited.document],
            "A built-in with a change awaiting review is imported with it, not left out.")
    }

    func testImagesOnlyLeftOutTemplatesUseAreNotUploaded() async throws {
        let server = MergeServer()
        let shared = UUID()
        let bytes = Data(repeating: 8, count: 256)
        let card = JournalItem(
            kind: "template", title: "Card",
            document: .init(blocks: [DocumentBlock(runs: [TextRun("Front")]), imageBlock(shared)]))
        let (mac, macSync) = try await otherDevice(server)
        _ = try await mac.addAttachment(bytes, id: shared)
        try await mac.save(card)
        try await macSync.synchronize()
        let local = try store(key: deviceKey)
        _ = try await local.addAttachment(bytes, id: shared)
        try await local.save(fresh(card))

        let (staged, _) = try await merge(local, into: server)
        let images = await server.images
        XCTAssertEqual(Array(images.keys), [shared], "The identical template isn't imported, nor is its image.")
        let derivedImage = MergePlan.derived(shared, server: await server.identity)
        let stagedImage = try await staged.hasAttachment(derivedImage)
        XCTAssertFalse(stagedImage)
    }

    func testShippedBuiltInTemplatesArePinned() {
        XCTAssertEqual(
            BuiltInTemplates.shipped.map(\.title),
            ["Daily Reflection", "Gratitude", "Workday Log", "Weekly Reflection"],
            "Entries are only ever appended.")
        XCTAssertEqual(
            BuiltInTemplates.shipped.map(\.text),
            [
                "# What went well?\n# What felt difficult?\n# What will I carry into tomorrow?",
                "# What am I grateful for today?",
                "# What I worked on\n# Decisions and context\n# Blockers and open questions\n# Where to pick up tomorrow",
                "# What stood out this week?\n# What did I learn?\n# What would I like to change?",
            ], "Shipped texts are never edited.")
        for template in BuiltInTemplates.all {
            XCTAssertTrue(BuiltInTemplates.isUnedited(fresh(template)), "\(template.title) has a shipped entry.")
        }
        var edited = fresh(BuiltInTemplates.all[0])
        edited.document = .plain("# What went well?")
        XCTAssertFalse(BuiltInTemplates.isUnedited(edited))
    }

    func testContentFromANewerVersionIsExplainedForMerging() {
        var item = JournalItem(kind: "entry", title: "From a newer version")
        item.preservedJSON = Data("{}".utf8)
        XCTAssertThrowsError(try ContentImport(items: [item], history: [], conflicts: [], for: .merge)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Update My Journal to merge the journals on this device. Some of them were saved by a newer version.")
        }
    }
}
