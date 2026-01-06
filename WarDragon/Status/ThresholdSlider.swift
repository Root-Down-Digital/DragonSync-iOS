//
//  ThresholdSlider.swift
//  WarDragon
//
//  Linear slider for warning threshold settings
//

import SwiftUI

struct ThresholdSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(value.wrappedValue))\(unit)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(color)
                    .fontWeight(.semibold)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            
            Slider(
                value: value,
                in: range,
                step: step
            ) {
                Text(title)
            } minimumValueLabel: {
                Text("\(Int(range.lowerBound))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } maximumValueLabel: {
                Text("\(Int(range.upperBound))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .tint(color)
        }
    }
}
