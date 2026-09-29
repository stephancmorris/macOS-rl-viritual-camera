import Foundation

nonisolated enum DirectorReplayFixtures {
    private static func subject(_ at: Double, channel: ChannelID = .b,
                                intended: Bool = true, movement: Double = 0) -> DirectorReplay.Event {
        .init(at: at, action: .subject(channel: channel, present: true, confidence: 0.95,
            intended: intended, framingReady: true, movement: movement))
    }
    static let calmSermon = DirectorReplay.Fixture(name: "calm sermon", duration: 60,
        events: [subject(9), .init(at: 20, action: .render(channel: .b))])
    static let walkingPastor = DirectorReplay.Fixture(name: "walking pastor", duration: 60,
        events: [subject(9, movement: 0.5), subject(20, movement: 0)])
    static let panelOfThree = DirectorReplay.Fixture(name: "panel of three", duration: 60,
        events: [subject(9, intended: false), subject(20, intended: true)])
    static let cameraBDrops = DirectorReplay.Fixture(name: "camera B drops", duration: 60,
        events: [subject(9), .init(at: 10, action: .source(channel: .b, missing: true)),
                 .init(at: 20, action: .source(channel: .b, missing: false))])
    static let operatorFights = DirectorReplay.Fixture(name: "operator fighting", duration: 60,
        events: [subject(9), .init(at: 10, action: .manualCommand),
                 .init(at: 11, action: .pause), .init(at: 20, action: .resume),
                 .init(at: 21, action: .operatorTake)])
    static let all = [calmSermon, walkingPastor, panelOfThree, cameraBDrops, operatorFights]
}
