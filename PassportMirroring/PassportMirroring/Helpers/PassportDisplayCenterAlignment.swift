//
//  PassportDisplayCenterAlignment.swift
//  PassportMirroring
//
//  Created by Yanan Li on 2026/9/7.
//

import SwiftUI

extension Alignment {
    static var aiPassportDisplayCenter: Alignment {
        .init(horizontal: .passportHorizontalDisplayCenter, vertical: .passportVerticalDisplayCenter)
    }
}

extension HorizontalAlignment {
    struct PassportDisplayCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[HorizontalAlignment.center]
        }
    }

    static let passportHorizontalDisplayCenter = HorizontalAlignment(PassportDisplayCenter.self)
}

extension VerticalAlignment {
    struct PassportDisplayCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let passportVerticalDisplayCenter = VerticalAlignment(PassportDisplayCenter.self)
}
