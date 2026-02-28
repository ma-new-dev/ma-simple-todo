//
//  Item.swift
//  To Do
//
//  Created by Mukul Arora on 28/02/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
