//
//  TypedCommandField.swift
//  CinematicCoreMacOS
//
//  Decision core, stage 5: one text field and one status line for typed
//  commands, in the next-shot panel. Return sends. While the field has focus
//  the console's plain keys (Escape, D, W…) go to the field, not to the show:
//  AlfiePlainKeyRouter yields to any focused text input.
//

import SwiftUI

struct TypedCommandField: View {
    @ObservedObject var controller: TypedCommandController
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Type a command for Preview", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit {
                    controller.submit(text)
                    text = ""
                }
                .accessibilityLabel("Command for Preview")
            Text(controller.status ?? "e.g. camera two, the person on the left, waist up")
                .font(.system(size: 11))
                .foregroundStyle(controller.status == nil ? AlfieColor.tertiaryText : AlfieColor.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityLabel(controller.status ?? "No command yet")
        }
    }
}
