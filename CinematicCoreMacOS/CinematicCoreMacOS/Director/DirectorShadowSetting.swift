//
//  DirectorShadowSetting.swift
//  CinematicCoreMacOS
//
//  The words for the "Record a Director shadow" setting (C-04). The setting
//  itself is `DeveloperFlags.directorShadowSettingKey`; it is read once per
//  launch, so this says what this launch is doing and what the next will do.
//

import Foundation

nonisolated enum DirectorShadowSetting {
    static let title = "Record a Director shadow"
    static let detail = "Alfie watches the show and keeps notes. It never changes a camera or Program. "
        + "Takes effect the next time Alfie starts."

    #if DEBUG
    static let debugBuild = true
    #else
    static let debugBuild = false
    #endif

    static func status(runningNow: Bool, savedSetting: Bool, debugBuild: Bool) -> String {
        if debugBuild { return "On. Debug builds always record." }
        switch (runningNow, savedSetting) {
        case (true, true): return "On"
        case (false, false): return "Off"
        case (false, true): return "Off now. On the next time Alfie starts."
        case (true, false): return "On now. Off the next time Alfie starts."
        }
    }
}
