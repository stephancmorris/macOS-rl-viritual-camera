import Testing
@testable import Alfie

struct AlfieCommandCatalogTests {
    private typealias Catalog = AlfieCommandCatalog

    @Test func everyCommandHasExactlyOneDefinition() {
        let ids = Catalog.definitions.map(\.id)
        #expect(Set(ids) == Set(Catalog.ID.allCases))
        #expect(ids.count == Set(ids).count)
        for definition in Catalog.definitions {
            #expect(Catalog.definition(for: definition.id) == definition)
            #expect(!definition.title.isEmpty)
        }
    }

    @Test func keyCombinationsAreUnique() {
        let shortcuts = Catalog.definitions.compactMap(\.shortcut)
        #expect(shortcuts.count == Set(shortcuts).count)
    }

    @Test func newCommandsCannotClaimReservedKeys() {
        for command in Catalog.definitions {
            guard let shortcut = command.shortcut else { continue }
            for reservation in Catalog.reservations where reservation.shortcut == shortcut {
                #expect(reservation.allowedOwner == command.id)
            }
        }
    }

    @Test func onlyTheThreeRetainedCommandsHaveReservationExceptions() {
        let retained = Catalog.reservations.compactMap(\.allowedOwner)
        #expect(Set(retained) == [.stopSession, .directorHand, .directorAdvance])
        #expect(retained.count == 3)
        for reservation in Catalog.reservations {
            guard let owner = reservation.allowedOwner else { continue }
            #expect(Catalog.definition(for: owner).shortcut == reservation.shortcut)
        }
    }

    @Test func standardMacOSApplicationKeysAreReserved() {
        let keys: [Character] = ["q", "w", ",", "h", "m", "n", "o", "s", "p", "f", "a", "c", "v", "x", "z"]
        for key in keys {
            let shortcut = Catalog.Shortcut(key: .character(key), modifiers: .command)
            #expect(Catalog.reservations.contains { $0.shortcut == shortcut && $0.allowedOwner == nil })
        }
    }

    @Test func takeNeverHasAKeyEquivalent() {
        let take = Catalog.definition(for: .take)
        #expect(take.shortcut == nil)
        #expect(!take.keysPending)
    }

    @Test func unspecifiedInterimKeysStayUnassigned() {
        let pending: Set<Catalog.ID> = [.detect, .wide, .fullBody, .waistUp, .pushIn, .pullOut]
        #expect(Set(Catalog.definitions.filter(\.keysPending).map(\.id)) == pending)
        for id in pending {
            #expect(Catalog.definition(for: id).shortcut == nil)
        }
    }

    @Test func stoppedModeKeysUseCommandAndCuesUsePlainNumbers() {
        let modes: [(Catalog.ID, Character)] = [(.singleCam, "1"), (.multiCam, "2"), (.webcam, "3")]
        let cues: [(Catalog.ID, Character)] = [
            (.cuePreview1, "1"), (.cuePreview2, "2"), (.cuePreview3, "3"), (.cuePreview4, "4")
        ]
        for (id, key) in modes {
            #expect(Catalog.definition(for: id).shortcut == .init(key: .character(key), modifiers: .command))
        }
        for (id, key) in cues {
            #expect(Catalog.definition(for: id).shortcut == .init(key: .character(key), modifiers: []))
        }
    }

    @Test func escapeInspectorAndRetainedKeysStayExact() {
        #expect(Catalog.definition(for: .cancel).shortcut == .init(key: .escape, modifiers: []))
        #expect(Catalog.definition(for: .showInspector).shortcut
                == .init(key: .character("i"), modifiers: [.command, .option]))
        #expect(Catalog.definition(for: .stopSession).shortcut
                == .init(key: .character("s"), modifiers: [.command, .option, .shift]))
        #expect(Catalog.definition(for: .directorHand).shortcut
                == .init(key: .character("h"), modifiers: [.command, .shift]))
        #expect(Catalog.definition(for: .directorAdvance).shortcut
                == .init(key: .returnKey, modifiers: [.command, .shift]))
    }

    @Test func catalogCanBeReadAwayFromMainActor() async {
        let definition = await Task.detached { Catalog.definition(for: .cuePreview1) }.value
        #expect(definition.shortcut == .init(key: .character("1"), modifiers: []))
    }
}
