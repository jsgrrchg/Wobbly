// Wobbly — Compiz-style wobbly windows for macOS
// Copyright (C) 2026 José Gurruchaga
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

/// Menu row with a label, slider and value, like the settings rows of the GNOME extension.
final class SliderMenuView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let decimals: Int
    private let onChange: (Double) -> Void

    init(title: String, value: Double, range: ClosedRange<Double>, decimals: Int, onChange: @escaping (Double) -> Void) {
        self.decimals = decimals
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 26))

        let font = NSFont.menuFont(ofSize: 0)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = font
        titleLabel.frame = NSRect(x: 22, y: 4, width: 80, height: 18)

        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                              target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        slider.controlSize = .small
        slider.frame = NSRect(x: 104, y: 3, width: 158, height: 20)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 264, y: 4, width: 42, height: 18)
        valueLabel.stringValue = format(value)

        addSubview(titleLabel)
        addSubview(slider)
        addSubview(valueLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func sliderChanged(_ slider: NSSlider) {
        let scale = pow(10, Double(decimals))
        let value = (slider.doubleValue * scale).rounded() / scale
        valueLabel.stringValue = format(value)
        onChange(value)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
