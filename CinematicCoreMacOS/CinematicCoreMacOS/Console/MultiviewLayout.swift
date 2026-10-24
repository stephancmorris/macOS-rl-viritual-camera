//
//  MultiviewLayout.swift
//  CinematicCoreMacOS
//
//  Pure geometry for the Multiview console. At the 1280×800 minimum window
//  every rect matches the CONSOLE / TAKE-BAR / NEXT-PANEL / INPUT-STRIP cards
//  exactly; wider windows grow both panes proportionally (16:9, fixed 32 pt
//  centre gutter), limited by the height so nothing below the panes clips.
//

import CoreGraphics
import SwiftUI

nonisolated struct MultiviewLayout: Equatable, Sendable {
    static let minimumSize = CGSize(width: 1280, height: 800)

    static let sideInset: CGFloat = 24
    static let centreGutter: CGFloat = 32
    static let headerHeight: CGFloat = 52
    /// Clears the window's traffic lights (hidden title bar).
    static let headerLeadingInset: CGFloat = 84
    /// Clears the inspector handle pinned top-right.
    static let headerTrailingInset: CGFloat = 64
    static let panesTop: CGFloat = 64
    static let barGap: CGFloat = 12
    static let barHeight: CGFloat = 70
    static let stripLabelGap: CGFloat = 14
    static let stripLabelHeight: CGFloat = 20
    static let tileGap: CGFloat = 12
    static let tileColumns: CGFloat = 4
    static let pillBottomInset: CGFloat = 12
    /// Everything below the tile row, reserved for the operator pill.
    static let pillBand: CGFloat = 114

    let size: CGSize
    let header: CGRect
    let previewPane: CGRect
    let programPane: CGRect
    let nextPanel: CGRect
    let takeBar: CGRect
    let stripLabel: CGRect
    let strip: CGRect
    let tileSize: CGSize
    let directorBar: CGRect

    init(size: CGSize) {
        self.size = size
        let paneWidth = max(0, min(Self.paneWidth(forWidth: size.width),
                                   Self.paneWidth(forHeight: size.height)))
        let paneHeight = (paneWidth * 9 / 16).rounded()
        let contentWidth = paneWidth * 2 + Self.centreGutter
        let left = ((size.width - contentWidth) / 2).rounded()
        let right = left + paneWidth + Self.centreGutter

        header = CGRect(x: 0, y: 0, width: size.width, height: Self.headerHeight)
        previewPane = CGRect(x: left, y: Self.panesTop, width: paneWidth, height: paneHeight)
        programPane = CGRect(x: right, y: Self.panesTop, width: paneWidth, height: paneHeight)

        let barY = previewPane.maxY + Self.barGap
        nextPanel = CGRect(x: left, y: barY, width: paneWidth, height: Self.barHeight)
        takeBar = CGRect(x: right, y: barY, width: paneWidth, height: Self.barHeight)

        let labelY = barY + Self.barHeight + Self.stripLabelGap
        stripLabel = CGRect(x: left, y: labelY, width: contentWidth, height: Self.stripLabelHeight)

        let tileWidth = (contentWidth - Self.tileGap * (Self.tileColumns - 1)) / Self.tileColumns
        tileSize = CGSize(width: tileWidth, height: (tileWidth * 9 / 16).rounded())
        strip = CGRect(x: left, y: stripLabel.maxY, width: contentWidth, height: tileSize.height)
        directorBar = CGRect(x: left, y: strip.maxY + 8, width: contentWidth, height: 36)
    }

    private static func paneWidth(forWidth width: CGFloat) -> CGFloat {
        (width - sideInset * 2 - centreGutter) / 2
    }

    /// Inverse of the vertical stack: fixed rows + pane height (w·9/16) +
    /// tile height (((2w + gutter − 3·gap) / 4)·9/16) must fit `height`.
    private static func paneWidth(forHeight height: CGFloat) -> CGFloat {
        let fixed = panesTop + barGap + barHeight + stripLabelGap + stripLabelHeight + pillBand
        let tileConstant = (centreGutter - tileGap * (tileColumns - 1)) / tileColumns
        // height − fixed = 9/16 · (w + w/2 + tileConstant)
        return ((height - fixed) * 16 / 9 - tileConstant) / 1.5
    }
}

/// Console colours shared by panes, bars, tiles and the pill.
enum ConsoleStyle {
    // Each follows the app's appearance (`AlfieColor`). Video panes force
    // Dark, so tallies drawn on footage keep the dark values.
    /// Program / Take / Edit Live red (#ff453a dark, #d70015 light).
    static let programRed = AlfieColor.danger
    /// Preview green (#30d158 dark, #157a34 light).
    static let previewGreen = AlfieColor.live
    /// Warning amber (#ff9f0a dark, #b25000 light).
    static let amber = AlfieColor.warning
    static let background = AlfieColor.background
    static let neutralFill = AlfieColor.ink.opacity(0.04)
    static let neutralBorder = AlfieColor.ink.opacity(0.12)
    static let disabledFill = AlfieColor.controlFill

    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }
}
