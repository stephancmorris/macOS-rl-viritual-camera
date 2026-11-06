//
//  TrackATrackingWebcamTests.swift
//  CinematicCoreMacOSTests
//
//  Track A (UX J3, J5): when people are clickable, the first-lock tip's
//  once-only rule, hit-testing on the letterboxed picture, and webcam.md's
//  live-state copy and announcements.
//

import CoreGraphics
import Foundation
import Testing
@testable import Alfie

@MainActor
struct TrackATrackingWebcamTests {
    // MARK: J3 · who is clickable

    @Test func detectingMakesPeopleClickable() {
        let tracking = TrackingPresentation.make(isDiscovering: true, isRecovering: false,
                                                 operatorGeometry: false, isLocked: false)
        #expect(tracking.candidatesClickable)
        #expect(!tracking.showsRecoveryHint)
    }

    @Test func holdAndWideWaitingAskForAClickOnThePerson() {
        let tracking = TrackingPresentation.make(isDiscovering: false, isRecovering: true,
                                                 operatorGeometry: false, isLocked: true)
        #expect(tracking.candidatesClickable)
        #expect(tracking.showsRecoveryHint)
        #expect(TrackingHintCopy.recovery == "Click the person to pick them up again.")
    }

    @Test func lockedShotIsNotClickableAndManualOrPanNeverIs() {
        let locked = TrackingPresentation.make(isDiscovering: false, isRecovering: false,
                                               operatorGeometry: false, isLocked: true)
        #expect(!locked.candidatesClickable)
        // A click on the picture in Manual moves the crop; Auto Pan ignores it.
        let manual = TrackingPresentation.make(isDiscovering: false, isRecovering: true,
                                               operatorGeometry: true, isLocked: true)
        #expect(!manual.candidatesClickable)
        #expect(!manual.showsRecoveryHint)
    }

    @Test func firstLockTipShowsOncePerUser() throws {
        let suite = "alfie.tests.firstLockTip.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!FirstLockTip.shouldShow(wasLocked: false, isLocked: false, defaults: defaults))
        #expect(FirstLockTip.shouldShow(wasLocked: false, isLocked: true, defaults: defaults))
        // Unlock and lock again: already shown.
        #expect(!FirstLockTip.shouldShow(wasLocked: false, isLocked: true, defaults: defaults))
        // Appearing while already locked is not a new lock.
        defaults.removeObject(forKey: FirstLockTip.defaultsKey)
        #expect(!FirstLockTip.shouldShow(wasLocked: true, isLocked: true, defaults: defaults))
    }

    @Test func firstLockTipDescribesWhatTheAppDoes() {
        // A click never changes a locked shot; a hold retargets.
        #expect(TrackingHintCopy.firstLock.contains("press and hold"))
        #expect(!TrackingHintCopy.firstLock.lowercased().contains("click someone"))
    }

    // MARK: J3 · geometry

    @Test func displayRectMatchesTheLetterboxedPicture() {
        // 16:9 in a square view: letterboxed top and bottom.
        let picture = TrackingGeometry.pictureRect(imageSize: CGSize(width: 1920, height: 1080),
                                                   viewSize: CGSize(width: 640, height: 640))
        #expect(abs(picture.height - 360) < 0.001)
        #expect(abs(picture.minY - 140) < 0.001)
        // Vision's bottom-left box becomes a top-left view rect.
        let rect = TrackingGeometry.displayRect(for: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                                                imageSize: CGSize(width: 1920, height: 1080),
                                                viewSize: CGSize(width: 640, height: 640))
        #expect(abs(rect.minX - 320) < 0.001)
        #expect(abs(rect.minY - 320) < 0.001)
        #expect(abs(rect.height - 180) < 0.001)
    }

    @Test func pointerPicksTheSmallestOverlappingPerson() {
        let near = UUID(), far = UUID()
        let boxes = [(id: far, rect: CGRect(x: 0, y: 0, width: 300, height: 300)),
                     (id: near, rect: CGRect(x: 100, y: 100, width: 80, height: 120))]
        #expect(TrackingGeometry.person(at: CGPoint(x: 120, y: 150), in: boxes) == near)
        #expect(TrackingGeometry.person(at: CGPoint(x: 20, y: 20), in: boxes) == far)
        #expect(TrackingGeometry.person(at: CGPoint(x: 400, y: 20), in: boxes) == nil)
    }

    // MARK: J5 · webcam.md

    @Test func liveStatesUseTheSpecifiedWords() {
        #expect(WebcamUsageCopy.status(for: .inUse).text == "Alfie camera · in use")
        #expect(WebcamUsageCopy.status(for: .notInUse).text == "Alfie camera · not in use yet")
        #expect(WebcamUsageCopy.status(for: .unknown).text == "Alfie camera · use status unavailable")
        #expect(WebcamUsageCopy.status(for: .inUse).help == "An app has started the Alfie camera stream.")
        #expect(WebcamUsageCopy.status(for: .notInUse).help == WebcamUsageCopy.tip)
        #expect(WebcamUsageCopy.status(for: .unknown).spoken
                == "Alfie camera use status is unavailable. Check your meeting app.")
        // Each state has its own shape as well as its colour.
        let symbols = Set([WebcamUsageState.inUse, .notInUse, .unknown].map { WebcamUsageCopy.status(for: $0).symbol })
        #expect(symbols.count == 3)
        #expect(WebcamUsageCopy.tip == "In Zoom, Meet or FaceTime, choose Alfie as your camera.")
        #expect(WebcamUsageCopy.tipDismissName == "Dismiss camera selection tip")
    }

    @Test func neverClaimsTheCallIsReceiving() {
        for state in [WebcamUsageState.inUse, .notInUse, .unknown] {
            let status = WebcamUsageCopy.status(for: state)
            for text in [status.text, status.help, status.spoken] {
                #expect(!text.contains("Zoom connected"))
                #expect(!text.lowercased().contains("live in your meeting"))
            }
        }
    }

    @Test func announcesEachChangeOnce() {
        #expect(WebcamUsageCopy.announcement(from: .unknown, to: .inUse, hasBeenInUse: false)
                == "Alfie camera is in use.")
        #expect(WebcamUsageCopy.announcement(from: .unknown, to: .notInUse, hasBeenInUse: false)
                == "Alfie camera is not in use yet. Choose Alfie as the camera in your meeting app.")
        #expect(WebcamUsageCopy.announcement(from: .inUse, to: .notInUse, hasBeenInUse: true)
                == "Alfie camera is no longer in use.")
        #expect(WebcamUsageCopy.announcement(from: .inUse, to: .unknown, hasBeenInUse: true)
                == "Alfie camera use status is unavailable. Check your meeting app.")
        #expect(WebcamUsageCopy.announcement(from: .inUse, to: .inUse, hasBeenInUse: true) == nil)
    }
}
