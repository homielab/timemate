//  Created by homielab.com

import SwiftUI

struct SessionStyle {
  let color: Color
  let iconName: String
}

extension SessionType {
  var style: SessionStyle {
    switch self {
    case .focus:
      return SessionStyle(
        color: .accentColor,
        iconName: "brain.head.profile"
      )
    case .shortBreak:
      return SessionStyle(
        color: .green,
        iconName: "cup.and.saucer.fill"
      )
    case .longBreak:
      return SessionStyle(
        color: .teal,
        iconName: "chair.lounge.fill"
      )
    }
  }
}
