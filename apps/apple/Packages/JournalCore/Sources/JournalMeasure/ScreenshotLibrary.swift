import Foundation
import JournalCore

/// The sample library the App Store screenshots show (docs/app-store/screenshots-plan.md): three journals of
/// synthetic entries with images, one custom template and an entry with earlier versions. It is written as a
/// complete app data folder, so the app opens it with `JOURNAL_DATA_DIR` and asks for the master password once.
struct ScreenshotLibrary {
    /// The part of the app's `configuration.json` a new password-protected library needs.
    private struct Configuration: Encodable {
        var recovery: RecoveryEnvelope
        var recoveryConfirmed = true
        var storageFolder: String
        var useBiometrics = false
        var lastJournalID: UUID
        var lastEntryID: UUID
        var passwordChecked = true
    }

    private struct Entry {
        var journal: Int
        var title: String
        var date: DateComponents
        var markdown: String
        var images: [String] = []
    }

    let directory: URL
    let photos: URL
    let password: String
    /// Earlier versions of "Bread, attempt four" come from edits made on another device. Libraries that will be
    /// uploaded to a new server leave them out, because those versions carry that device's revisions.
    let includesHistory: Bool

    static let imageDescriptions = [
        "coffee.jpg": "A cup of coffee on a wooden table by a sunny window",
        "tomatoes.jpg": "A bowl of red and green tomatoes on a windowsill",
        "loaf.jpg": "A sourdough loaf cooling on a wire rack",
        "path.jpg": "A forest path covered in wet autumn leaves",
        "river.jpg": "Riverside houses and boats at sunset",
    ]

    func seed() async throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw MeasurementError.existingFixture }
        guard password.count >= VaultCrypto.minimumPasswordLength else { throw MeasurementError.invalidArguments }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = try VaultCrypto.generateKey()
        let recovery = try VaultCrypto.makeRecovery(masterKey: key, phrase: password, formatVersion: 2).0
        let folder = "vault-" + UUID().uuidString.lowercased()
        let store = try JournalStore(
            directory: directory.appendingPathComponent(folder), key: key, protection: recovery.contentProtection)
        var templates: [String: UUID] = [:]
        for template in BuiltInTemplates.all {
            try await store.save(template)
            templates[template.title] = template.id
        }
        let bookNotes = JournalItem(
            kind: "template", title: "Book Notes",
            document: JournalDocument(markdown: "## Title and author\n\n## What stayed with me\n\n## One idea to try\n")
        )
        try await store.save(bookNotes)
        let names = ["Personal", "Work", "Travel"]
        let defaults = ["Daily Reflection", "Workday Log", nil]
        var journals: [JournalItem] = []
        for (index, name) in names.enumerated() {
            var journal = JournalItem(
                kind: "journal", title: name, date: Date(timeIntervalSince1970: 1_788_000_000 + Double(index) * 60))
            journal.defaultTemplateID = defaults[index].flatMap { templates[$0] }
            try await store.save(journal)
            journals.append(journal)
        }
        var images: [String: UUID] = [:]
        for name in Self.imageDescriptions.keys.sorted() {
            images[name] = try await store.addAttachment(Data(contentsOf: photos.appendingPathComponent(name)))
        }
        var saved: [String: JournalItem] = [:]
        for entry in Self.entries {
            var markdown = entry.markdown
            for name in entry.images {
                guard let id = images[name], let description = Self.imageDescriptions[name] else {
                    throw MeasurementError.resourceUnavailable
                }
                markdown = markdown.replacingOccurrences(
                    of: "[image: \(name)]", with: "![\(description)](attachments/\(id.uuidString.lowercased()))")
            }
            guard let date = Calendar(identifier: .gregorian).date(from: entry.date) else {
                throw MeasurementError.invalidArguments
            }
            let item = JournalItem(
                kind: "entry", journalID: journals[entry.journal].id, title: entry.title,
                document: JournalDocument(markdown: markdown), date: date)
            saved[entry.title] = try await store.save(item)
        }
        if includesHistory, let bread = saved["Bread, attempt four"] {
            try await addHistory(to: store, key: key, entry: bread, loaf: images["loaf.jpg"])
        }
        try await store.close()
        guard let first = saved["Slow Sunday"] else { throw MeasurementError.contentMismatch }
        let configuration = Configuration(
            recovery: recovery, storageFolder: folder, lastJournalID: journals[0].id, lastEntryID: first.id)
        try JournalCoding.encoder().encode(configuration).write(
            to: directory.appendingPathComponent("configuration.json"), options: .atomic)
    }

    /// Three earlier versions of the bread entry, as edits from the iPad that this device took over: the table
    /// arrives first, then the last line, then a corrected word.
    private func addHistory(to store: JournalStore, key: Data, entry: JournalItem, loaf: UUID?) async throws {
        guard let loaf else { throw MeasurementError.resourceUnavailable }
        let image = "![\(Self.imageDescriptions["loaf.jpg"] ?? "")](attachments/\(loaf.uuidString.lowercased()))"
        let steps =
            "Finally a loaf with a proper ear. What changed:\n\n1. A longer cold proof, 14 hours in the fridge\n"
            + "2. A little less water\n3. Scoring at a lower angle\n\n" + image + "\n"
        let table =
            "\n| Attempt | Proof | Result |\n| --- | --- | --- |\n| 1 | 4 hours | Flat |\n| 2 | 8 hours | Dense |\n"
            + "| 3 | 12 hours | Better |\n| 4 | 14 hours | Just right |\n"
        let withLine = steps + table + "\nKept the evening free afterwards and read on the sofa.\n"
        let fixed = { (text: String) in text.replacingOccurrences(of: "at a lower angle", with: "at a shallower angle")
        }
        let other = directory.appendingPathComponent("other-device")
        let otherStore = try JournalStore(directory: other, key: key)
        var local = entry
        local.document = JournalDocument(markdown: steps)
        local = try await store.save(local)
        // The iPad adds the table while this device still has the first draft; this device takes the iPad's.
        local = try await review(
            store, otherStore, local: local, remote: steps + table, revision: 1, choice: .remote,
            at: entry.date.addingTimeInterval(1_500))
        // This device adds the last line while the iPad corrects a word; this device keeps its own.
        local.document = JournalDocument(markdown: withLine)
        local.modifiedAt = entry.date.addingTimeInterval(3_000)
        local = try await store.save(local)
        local = try await review(
            store, otherStore, local: local, remote: fixed(steps + table), revision: 2, choice: .local,
            at: entry.date.addingTimeInterval(3_300))
        local.document = JournalDocument(markdown: fixed(withLine))
        try await store.save(local)
        try await otherStore.close()
        try FileManager.default.removeItem(at: other)
    }

    private func review(
        _ store: JournalStore, _ otherStore: JournalStore, local: JournalItem, remote markdown: String,
        revision: Int64, choice: ConflictChoice, at date: Date
    ) async throws -> JournalItem {
        var remote = local
        remote.storedVersion = nil
        remote.document = JournalDocument(markdown: markdown)
        remote.modifiedAt = date
        try await otherStore.save(remote)
        guard let payload = try await otherStore.pending().first(where: { $0.recordID == local.id })?.payload else {
            throw MeasurementError.contentMismatch
        }
        let iPad = UUID(uuidString: "00000000-0000-0000-0000-0000000000a2") ?? UUID()
        try await store.recordConflict(
            RemoteChange(
                cursor: 0, recordId: local.id, revision: revision, kind: "entry", payload: payload, deviceId: iPad,
                modifiedAt: date))
        guard let conflict = try await store.conflicts().first(where: { $0.id == local.id }) else {
            throw MeasurementError.contentMismatch
        }
        return try await store.resolve(conflict, choice: choice)
    }

    private static func day(_ day: Int, _ hour: Int, _ minute: Int) -> DateComponents {
        DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: .current, year: 2026, month: 9, day: day, hour: hour,
            minute: minute)
    }

    private static let entries: [Entry] = [
        Entry(
            journal: 0, title: "Slow Sunday", date: day(27, 9, 12),
            markdown: """
                Woke up before the alarm and left my phone in the other room. Made coffee, opened the window and \
                listened to the street wake up. The light comes in lower now. Autumn is arriving one morning at a time.

                [image: coffee.jpg]

                ## Worth keeping from this week

                - The evening walk along the river on Tuesday
                - Finally fixing the wobbly kitchen chair
                - Saying no to one more commitment, and meaning it

                ## Today

                - [x] Feed the sourdough starter
                - [ ] Call my sister
                - [ ] Leave the evening empty

                > Nothing is in a hurry today, including me.

                """, images: ["coffee.jpg"]),
        Entry(
            journal: 0, title: "Daily Reflection", date: day(26, 21, 40),
            markdown: """
                ## What went well?

                Long lunch outside with Sam. We talked about everything except work, which was exactly right.

                ## What felt difficult?

                Staying focused in the afternoon. Too many tabs open, in the browser and in my head.

                ## What will I carry into tomorrow?

                Close the laptop by six. Walk first, then decide what the evening is for.

                """),
        Entry(
            journal: 0, title: "The last tomatoes", date: day(24, 19, 5),
            markdown: """
                Picked the last of the tomatoes before the cold nights arrive. Some are still green; they're \
                ripening on the windowsill next to the basil.

                [image: tomatoes.jpg]

                Evening walk after dinner. The sky was pink for ten minutes, and then it wasn't. Slept well.

                Next year: fewer plants, more space between them.

                """, images: ["tomatoes.jpg"]),
        Entry(
            journal: 0, title: "Gratitude", date: day(23, 22, 15),
            markdown: """
                ## What am I grateful for today?

                - A neighbor who waters the plants without being asked
                - The first soup of the season
                - A letter from an old friend, the paper kind

                """),
        Entry(
            journal: 0, title: "Bread, attempt four", date: day(21, 18, 30),
            markdown: """
                Finally a loaf with a proper ear. What changed:

                1. A longer cold proof, 14 hours in the fridge
                2. A little less water
                3. Scoring at a shallower angle

                [image: loaf.jpg]

                | Attempt | Proof | Result |
                | --- | --- | --- |
                | 1 | 4 hours | Flat |
                | 2 | 8 hours | Dense |
                | 3 | 12 hours | Better |
                | 4 | 14 hours | Just right |

                Kept the evening free afterwards and read on the sofa.

                """, images: ["loaf.jpg"]),
        Entry(
            journal: 0, title: "Rainy walk", date: day(19, 11, 20),
            markdown: """
                It rained all morning, so I went out anyway. The woods smelled of wet leaves and nobody else was on \
                the path. Forty minutes, no podcast, just rain on my hood.

                [image: path.jpg]

                Walking without headphones is when the good ideas show up.

                """, images: ["path.jpg"]),
        Entry(
            journal: 0, title: "A quiet chapter", date: day(17, 22, 45),
            markdown: """
                Reading before bed again, one chapter a night instead of one more episode.

                > Small, steady, and kind to yourself. That's the whole plan.

                Wrote that on the first page of a new notebook years ago. Still true.

                """),
        Entry(
            journal: 0, title: "A good conversation", date: day(15, 21, 30),
            markdown: """
                Walked along the river after dinner with Priya. We talked about slowing down without falling behind.

                She keeps two evenings a week free and protects them like meetings. Trying it: Tuesdays and Sundays.

                """),
        Entry(
            journal: 1, title: "Workday Log", date: day(24, 17, 40),
            markdown: """
                ## What I worked on

                - Drafted the onboarding checklist for new team members
                - Reviewed the quarterly plan with Alex

                ## Decisions and context

                Ship the smaller version first and learn from it, rather than wait for everything.

                ## Blockers and open questions

                - [ ] Who covers support in the first week of October?

                ## Where to pick up tomorrow

                Finish the checklist and share it for comments.

                """),
        Entry(
            journal: 1, title: "Week 39", date: day(25, 16, 50),
            markdown: """
                ## What stood out this week?

                The planning session on Wednesday: short, focused, and everyone left with one clear next step.

                ## What did I learn?

                Writing the decision down first makes the meeting half as long.

                ## What would I like to change?

                Fewer status meetings, more short written updates.

                """),
        Entry(
            journal: 1, title: "Offsite ideas", date: day(22, 14, 10),
            markdown: """
                Three options for the team day in November.

                | Option | Good | Less good |
                | --- | --- | --- |
                | A day in the city | Easy to reach | Feels like a normal day |
                | Cabin by the lake | Room to think | Long drive |
                | Walk and talk | Fresh air, low cost | Depends on the weather |

                Leaning towards the cabin, with a long walk on the second morning.

                """),
        Entry(
            journal: 1, title: "Help center kickoff", date: day(16, 11, 0),
            markdown: """
                Started the help center project. Goals for the first month:

                1. Talk to five customers
                2. List the ten most common questions
                3. Draft answers in plain language

                - [x] Book the customer calls
                - [ ] Share the draft outline

                """),
        Entry(
            journal: 2, title: "Porto, day two", date: day(12, 22, 5),
            markdown: """
                Walked down to the river in the late afternoon. Boats, gulls, and the whole city turning orange as \
                the sun went down. Grilled fish at a small place with six tables and no menu.

                [image: river.jpg]

                - [x] Tile museum
                - [x] Walk across the bridge
                - [ ] Tram up the hill tomorrow

                """, images: ["river.jpg"]),
        Entry(
            journal: 2, title: "Train north", date: day(11, 18, 40),
            markdown: """
                Six hours on the train and I didn't open the laptop once. Watched the coast go by, wrote two \
                postcards, and fell asleep somewhere after Coimbra.

                """),
        Entry(
            journal: 2, title: "Packing list", date: day(8, 20, 0),
            markdown: """
                - [x] Passport
                - [x] Chargers
                - [x] Walking shoes
                - [x] Rain jacket
                - [ ] Book for the train
                - [ ] Notebook

                """),
    ]
}
