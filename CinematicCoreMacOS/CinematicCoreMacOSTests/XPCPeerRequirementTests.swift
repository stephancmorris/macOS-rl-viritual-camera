//
//  XPCPeerRequirementTests.swift
//  CinematicCoreMacOSTests
//
//  CR-003 / CR-016: the virtual-camera XPC link accepts a peer only when its
//  signature satisfies an Apple-anchored requirement for the expected bundle
//  identifier and team, not just a matching identifier string.
//

import Foundation
import Security
import Testing
@testable import Alfie

struct XPCPeerRequirementTests {
    private let team = "ABCDE12345"

    @Test func requirementCompilesAndNamesIdentifierAndTeam() throws {
        let text = try #require(XPCPeerRequirement.requirement(
            identifier: XPCPeerRequirement.extensionIdentifier, teamID: team))
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
        #expect(requirement != nil)
        #expect(text.contains("anchor apple generic"))
        #expect(text.contains("identifier \"Morris.CinematicCoreMacOS.CinematicCoreExtension\""))
        #expect(text.contains("certificate leaf[subject.OU] = \"\(team)\""))
    }

    @Test func valuesThatCouldInjectIntoTheRequirementAreRefused() {
        #expect(XPCPeerRequirement.requirement(identifier: "a.b", teamID: "") == nil)
        #expect(XPCPeerRequirement.requirement(identifier: "a.b", teamID: "abcde12345") == nil)
        #expect(XPCPeerRequirement.requirement(identifier: "a.b", teamID: "X\" or anchor apple") == nil)
        #expect(XPCPeerRequirement.requirement(identifier: "", teamID: team) == nil)
        #expect(XPCPeerRequirement.requirement(identifier: "a\" or anchor apple or identifier \"b", teamID: team) == nil)
    }

    /// The review's case: an ad-hoc signature that carries the expected
    /// identifier. The unit-test host is built with CODE_SIGNING_ALLOWED=NO,
    /// so it is at most ad-hoc signed; a requirement for its own identifier
    /// must still reject it.
    @Test func adHocCodeWithTheExpectedIdentifierFailsTheRequirement() throws {
        var code: SecCode?
        #expect(SecCodeCopySelf([], &code) == errSecSuccess)
        let selfCode = try #require(code)
        let ownIdentifier = Bundle.main.bundleIdentifier ?? "Morris.CinematicCoreMacOS"
        let text = try #require(XPCPeerRequirement.requirement(identifier: ownIdentifier, teamID: team))
        var requirement: SecRequirement?
        #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess)
        let compiled = try #require(requirement)
        #expect(SecCodeCheckValidity(selfCode, [], compiled) != errSecSuccess)
    }

    @Test func unsignedBuildHasNoExtensionRequirement() {
        // Without a team signature there is nothing to verify the peer against;
        // the host then refuses to connect instead of connecting unchecked.
        guard XPCPeerRequirement.ownTeamIdentifier() == nil else { return }
        #expect(XPCPeerRequirement.forExtension() == nil)
    }
}
