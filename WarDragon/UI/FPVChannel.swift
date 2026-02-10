//
//  FPVChannel.swift
//  WarDragon
//
//  Created by Luke on 2/10/26.
//

import Foundation
import SwiftUI

// MARK: - FPV Channel Detection
struct FPVChannel {
    let name: String
    let frequency: Int
    let band: String
    
    var icon: String {
        switch band {
        case "R": return "r.circle.fill"
        case "A": return "a.circle.fill"
        case "B": return "b.circle.fill"
        case "E": return "e.circle.fill"
        case "F": return "f.circle.fill"
        case "IMD": return "i.circle.fill"
        case "D": return "d.circle.fill"
        case "L": return "l.circle.fill"
        default: return "circle.fill"
        }
    }
    
    var color: Color {
        switch band {
        case "R": return .red
        case "A": return .blue
        case "B": return .green
        case "E": return .orange
        case "F": return .purple
        case "IMD": return .pink
        case "D": return .cyan
        case "L": return .yellow
        default: return .gray
        }
    }
    
    static let allChannels: [FPVChannel] = [
        // Race Band (R)
        FPVChannel(name: "R1", frequency: 5658, band: "R"),
        FPVChannel(name: "R2", frequency: 5695, band: "R"),
        FPVChannel(name: "R3", frequency: 5732, band: "R"),
        FPVChannel(name: "R4", frequency: 5769, band: "R"),
        FPVChannel(name: "R5", frequency: 5806, band: "R"),
        FPVChannel(name: "R6", frequency: 5843, band: "R"),
        FPVChannel(name: "R7", frequency: 5880, band: "R"),
        FPVChannel(name: "R8", frequency: 5917, band: "R"),
        
        // Band A
        FPVChannel(name: "A1", frequency: 5865, band: "A"),
        FPVChannel(name: "A2", frequency: 5845, band: "A"),
        FPVChannel(name: "A3", frequency: 5825, band: "A"),
        FPVChannel(name: "A4", frequency: 5805, band: "A"),
        FPVChannel(name: "A5", frequency: 5785, band: "A"),
        FPVChannel(name: "A6", frequency: 5765, band: "A"),
        FPVChannel(name: "A7", frequency: 5745, band: "A"),
        FPVChannel(name: "A8", frequency: 5725, band: "A"),
        
        // Band B
        FPVChannel(name: "B1", frequency: 5733, band: "B"),
        FPVChannel(name: "B2", frequency: 5752, band: "B"),
        FPVChannel(name: "B3", frequency: 5771, band: "B"),
        FPVChannel(name: "B4", frequency: 5790, band: "B"),
        FPVChannel(name: "B5", frequency: 5809, band: "B"),
        FPVChannel(name: "B6", frequency: 5828, band: "B"),
        FPVChannel(name: "B7", frequency: 5847, band: "B"),
        FPVChannel(name: "B8", frequency: 5866, band: "B"),
        
        // Band E
        FPVChannel(name: "E1", frequency: 5705, band: "E"),
        FPVChannel(name: "E2", frequency: 5685, band: "E"),
        FPVChannel(name: "E3", frequency: 5665, band: "E"),
        FPVChannel(name: "E4", frequency: 5645, band: "E"),
        FPVChannel(name: "E5", frequency: 5885, band: "E"),
        FPVChannel(name: "E6", frequency: 5905, band: "E"),
        FPVChannel(name: "E7", frequency: 5925, band: "E"),
        FPVChannel(name: "E8", frequency: 5945, band: "E"),
        
        // Fatshark/NexwaveRF (F)
        FPVChannel(name: "F1", frequency: 5740, band: "F"),
        FPVChannel(name: "F2", frequency: 5760, band: "F"),
        FPVChannel(name: "F3", frequency: 5780, band: "F"),
        FPVChannel(name: "F4", frequency: 5800, band: "F"),
        FPVChannel(name: "F5", frequency: 5820, band: "F"),
        FPVChannel(name: "F6", frequency: 5840, band: "F"),
        FPVChannel(name: "F7", frequency: 5860, band: "F"),
        FPVChannel(name: "F8", frequency: 5880, band: "F"),
        
        // ImmersionRC/DJI (IMD)
        FPVChannel(name: "IMD1", frequency: 5658, band: "IMD"),
        FPVChannel(name: "IMD2", frequency: 5695, band: "IMD"),
        FPVChannel(name: "IMD3", frequency: 5732, band: "IMD"),
        FPVChannel(name: "IMD4", frequency: 5769, band: "IMD"),
        FPVChannel(name: "IMD5", frequency: 5806, band: "IMD"),
        FPVChannel(name: "IMD6", frequency: 5843, band: "IMD"),
        
        // DJI Band (D)
        FPVChannel(name: "D1", frequency: 5660, band: "D"),
        FPVChannel(name: "D2", frequency: 5695, band: "D"),
        FPVChannel(name: "D3", frequency: 5735, band: "D"),
        FPVChannel(name: "D4", frequency: 5770, band: "D"),
        FPVChannel(name: "D5", frequency: 5805, band: "D"),
        FPVChannel(name: "D6", frequency: 5878, band: "D"),
        FPVChannel(name: "D7", frequency: 5914, band: "D"),
        FPVChannel(name: "D8", frequency: 5839, band: "D"),
        
        // Low Band (L)
        FPVChannel(name: "L1", frequency: 5362, band: "L"),
        FPVChannel(name: "L2", frequency: 5399, band: "L"),
        FPVChannel(name: "L3", frequency: 5436, band: "L"),
        FPVChannel(name: "L4", frequency: 5473, band: "L"),
        FPVChannel(name: "L5", frequency: 5510, band: "L"),
        FPVChannel(name: "L6", frequency: 5547, band: "L"),
        FPVChannel(name: "L7", frequency: 5584, band: "L"),
        FPVChannel(name: "L8", frequency: 5621, band: "L"),
    ]
    
    static func detectChannel(fromFrequency frequency: String) -> FPVChannel? {
        // Try to parse frequency as integer (MHz)
        guard let freqInt = Int(frequency) else { return nil }
        
        // Look for exact match
        if let exactMatch = allChannels.first(where: { $0.frequency == freqInt }) {
            return exactMatch
        }
        
        // Look for close match (within 5 MHz tolerance)
        let tolerance = 5
        return allChannels.first { channel in
            abs(channel.frequency - freqInt) <= tolerance
        }
    }
}
