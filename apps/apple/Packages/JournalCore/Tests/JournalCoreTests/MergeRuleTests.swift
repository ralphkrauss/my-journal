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
        var macGratitude = try XCTUnwrap(BuiltInTemplates.asEarlierBuildsCreated().first { $0.title == "Gratitude" })
        macGratitude.document = .plain("Edited on the Mac")
        let macRecipe = template("Recipe", "Ingredients")
        let macRetro = template("Retro", "What went well")
        for item in [macGratitude, macRecipe, macRetro, template("Standup", "A"), template("Standup", "B")] {
            try await mac.save(item)
        }
        try await macSync.synchronize()

        let local = try store(key: deviceKey)
        let unedited = try XCTUnwrap(BuiltInTemplates.asEarlierBuildsCreated().first { $0.title == "Gratitude" })
        let dailyReflection = try XCTUnwrap(
            BuiltInTemplates.asEarlierBuildsCreated().first { $0.title == "Daily Reflection" })
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

        let (staged, _) = try await merge(local, into: server)
        let result = try await downloaded(server).items()
        XCTAssertEqual(
            live(result, "template", "Gratitude").map(\.document), [macGratitude.document],
            "An unedited built-in is left out even when the server's copy was edited, and is not a conflict.")
        XCTAssertEqual(
            live(result, "template", "Daily Reflection").count, 1,
            "An unedited built-in whose name the server lacks is added, so nothing is lost.")
        XCTAssertEqual(live(result, "template", "Standup").count, 3, "With several of a name, each is added.")
        XCTAssertEqual(live(result, "template", "Retro").map(\.id), [macRetro.id])
        XCTAssertEqual(
            result.filter { $0.title == "Retro" && $0.deletedAt != nil }.count, 1,
            "A template in Recently Deleted is imported as it is, without matching.")
        func journal(_ title: String) throws -> JournalItem { try XCTUnwrap(result.first { $0.title == title }) }
        XCTAssertEqual(
            try journal("Travel").defaultTemplateID, macRecipe.id, "It follows the template that kept its identity.")
        XCTAssertEqual(
            try journal("Notes").defaultTemplateID, live(result, "template", "Daily Reflection").first?.id,
            "It follows the added built-in.")
        let addedStandup = try XCTUnwrap(
            live(result, "template", "Standup").first { $0.document == standup.document })
        XCTAssertEqual(try journal("Ideas").defaultTemplateID, addedStandup.id)

        // The template that differs is settled by the merge: this device's version, with its image, stays the template
        // and is sent with the image; the server's version is a template of its own.
        let pendingReviews = try await staged.conflicts()
        XCTAssertTrue(pendingReviews.isEmpty)
        let resolved = try await downloaded(server)
        let keptRecipe = try await resolved.item(macRecipe.id)
        let mergedImage = try XCTUnwrap(keptRecipe?.document.attachmentIDs.first)
        XCTAssertEqual(keptRecipe?.document.attachmentIDs, [mergedImage])
        let uploaded = await server.images[mergedImage]
        XCTAssertNotNil(uploaded)
        let keptImage = try await resolved.attachment(mergedImage)
        XCTAssertEqual(keptImage, image)
        let serverVersion = live(try await resolved.items(), "template", "Recipe (other version)")
        XCTAssertEqual(serverVersion.map(\.document), [macRecipe.document])
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

    func testATemplateThatDiffersOnlyInParagraphsKeepsBothVersionsAndIsNotSkipped() async throws {
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
        XCTAssertTrue(reviews.isEmpty)
        let result = try await downloaded(server).items()
        XCTAssertEqual(live(result, "template", "Plan").map(\.id), [serverPlan.id])
        XCTAssertEqual(live(result, "template", "Plan").first?.document.markdown, localPlan.document.markdown)
        XCTAssertEqual(
            live(result, "template", "Plan (other version)").first?.document.markdown, serverPlan.document.markdown,
            "Not skipped as the same: the server's version is kept")
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
        let builtIn = try XCTUnwrap(BuiltInTemplates.asEarlierBuildsCreated().first { $0.title == "Gratitude" })
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
        XCTAssertTrue(reviews.isEmpty)
        let templates = try await staged.items().filter { $0.kind == "template" && $0.title.hasPrefix("Gratitude") }
        XCTAssertTrue(
            templates.contains { $0.document == edited.document },
            "A built-in with another version is imported with it, not left out.")
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

    /// Libraries from builds that created built-in templates and from this one, which doesn't, merge both ways with
    /// each built-in once, and nothing either side made is lost (no-built-in-templates-2026-10-04.md).
    func testBuiltInTemplatesEndUpOnceWhicheverLibraryHasThem() async throws {
        for builtInsOnServer in [true, false] {
            let server = MergeServer()
            let (mac, macSync) = try await otherDevice(server)
            let serverJournal = JournalItem(kind: "journal", title: "Default")
            try await mac.save(serverJournal)
            try await mac.save(JournalItem(kind: "entry", journalID: serverJournal.id, title: "On the server"))
            try await mac.save(JournalItem(kind: "template", title: "Standup", document: .plain("Yesterday, today")))
            if builtInsOnServer {
                for template in BuiltInTemplates.asEarlierBuildsCreated() { try await mac.save(template) }
            }
            try await macSync.synchronize()

            let local = try store(key: deviceKey)
            let localJournal = JournalItem(kind: "journal", title: "Default")
            if !builtInsOnServer {
                for template in BuiltInTemplates.asEarlierBuildsCreated() { try await local.save(template) }
            }
            try await local.save(localJournal)
            try await local.save(JournalItem(kind: "entry", journalID: localJournal.id, title: "On this device"))
            try await local.save(JournalItem(kind: "template", title: "Ideas", document: .plain("What if")))

            try await merge(local, into: server)
            let result = try await downloaded(server).items()
            let side = builtInsOnServer ? "on the server" : "on this device"
            for title in BuiltInTemplates.shipped.map(\.title) + ["Standup", "Ideas"] {
                XCTAssertEqual(live(result, "template", title).count, 1, "\(title), built-ins \(side)")
            }
            XCTAssertTrue(
                live(result, "template", "Gratitude").allSatisfy(BuiltInTemplates.isUnedited),
                "Built-ins \(side) arrive unchanged.")
            let entries = result.filter { $0.kind == "entry" }.map(\.title)
            XCTAssertEqual(Set(entries), ["On the server", "On this device"], "Built-ins \(side)")
        }
    }

    /// A second library with built-ins merging after the first doesn't add them again, and a built-in the server has
    /// only in Recently Deleted stays deleted there instead of coming back, without a second copy of the same text.
    func testBuiltInsArentAddedTwiceOrBroughtBackFromRecentlyDeleted() async throws {
        let server = MergeServer()
        let (mac, macSync) = try await otherDevice(server)
        try await mac.save(JournalItem(kind: "journal", title: "Default"))
        try await macSync.synchronize()
        for device in ["first", "second"] {
            let local = try store(key: deviceKey)
            try await local.save(JournalItem(kind: "journal", title: "Default"))
            try await local.save(JournalItem(kind: "entry", title: "From the \(device) device"))
            for template in BuiltInTemplates.asEarlierBuildsCreated() { try await local.save(template) }
            try await merge(local, into: server)
        }
        var result = try await downloaded(server).items()
        for title in BuiltInTemplates.shipped.map(\.title) {
            XCTAssertEqual(live(result, "template", title).count, 1, "\(title) is added once.")
        }

        try await macSync.synchronize()
        let onMac = try await mac.items()
        var gratitude = try XCTUnwrap(live(onMac, "template", "Gratitude").first)
        gratitude.deletedAt = Date(timeIntervalSince1970: 1_900_000_000)
        try await mac.save(gratitude)
        var workday = try XCTUnwrap(live(onMac, "template", "Workday Log").first)
        workday.document = .plain("Edited, then deleted")
        workday.deletedAt = Date(timeIntervalSince1970: 1_900_000_000)
        try await mac.save(workday)
        try await macSync.synchronize()
        let third = try store(key: deviceKey)
        try await third.save(JournalItem(kind: "entry", title: "From the third device"))
        for template in BuiltInTemplates.asEarlierBuildsCreated() { try await third.save(template) }
        try await merge(third, into: server)
        result = try await downloaded(server).items()
        func deleted(_ title: String) -> Int {
            result.filter { $0.kind == "template" && $0.title == title && $0.deletedAt != nil }.count
        }
        for title in ["Gratitude", "Workday Log"] {
            XCTAssertTrue(live(result, "template", title).isEmpty, "\(title): the deletion isn't undone.")
        }
        XCTAssertEqual(deleted("Gratitude"), 1, "The same text is already in Recently Deleted.")
        XCTAssertEqual(deleted("Workday Log"), 2, "This device's different copy is kept in Recently Deleted.")
        XCTAssertEqual(live(result, "template", "Weekly Reflection").count, 1)
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
        for template in BuiltInTemplates.asEarlierBuildsCreated() {
            XCTAssertTrue(BuiltInTemplates.isUnedited(template), "\(template.title) has a shipped entry.")
        }
        var edited = BuiltInTemplates.asEarlierBuildsCreated()[0]
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
