//
//  VolumeHUDView.swift
//  FocusriteVolumeControl
//
//  Floating volume HUD overlay — matches macOS system volume OSD layout.
//  Device name on top, speaker icons flanking a volume bar.
//

import SwiftUI
import Combine

// MARK: - View Model

class VolumeHUDViewModel: ObservableObject {
    @Published var volumeDb: Double = -20
    @Published var isMuted: Bool = false
    @Published var allowGain: Bool = false

    // Same perceptual curve as VolumeController: 50% slider = -16 dB
    private let curveExponent: Double = 0.197

    /// Convert dB to perceptual percent (0–100, or above 100 for overgain)
    private func dbToPercent(_ db: Double) -> Double {
        guard db > -127 else { return 0 }
        let normalized = (db + 127.0) / 127.0
        return 100.0 * pow(normalized, 1.0 / curveExponent)
    }

    /// Max percent for the full bar width
    private var maxPercent: Double {
        allowGain ? dbToPercent(6.0) : 100.0
    }

    /// Fraction of the bar to fill (0...1), using perceptual curve
    var fillFraction: CGFloat {
        guard !isMuted else { return 0 }
        let maxDb = allowGain ? 6.0 : 0.0
        let clamped = max(-127.0, min(maxDb, volumeDb))
        let percent = dbToPercent(clamped)
        return CGFloat(min(1.0, percent / maxPercent))
    }

    /// Where the 0 dB tick sits as a fraction of bar width (only meaningful when allowGain)
    var zeroDbTickFraction: CGFloat {
        guard allowGain else { return 1.0 }
        return CGFloat(100.0 / maxPercent)
    }
}

// MARK: - HUD View

struct VolumeHUDView: View {
    @ObservedObject var viewModel: VolumeHUDViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Device name
            Text("Scarlett Solo 4th Gen")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            // Volume bar row: speaker-quiet | bar | speaker-loud
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))

                VolumeBarView(
                    fillFraction: viewModel.fillFraction,
                    zeroDbTickFraction: viewModel.zeroDbTickFraction,
                    showTick: viewModel.allowGain,
                    isOvergain: viewModel.allowGain && viewModel.volumeDb > 0 && !viewModel.isMuted
                )
                .frame(height: 6)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 280)
    }
}

// MARK: - Volume Bar

struct VolumeBarView: View {
    let fillFraction: CGFloat
    let zeroDbTickFraction: CGFloat
    let showTick: Bool
    let isOvergain: Bool

    private let barHeight: CGFloat = 6
    private let cornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Dark track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.15))

                // Fill bar
                if fillFraction > 0 {
                    if isOvergain {
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: width * zeroDbTickFraction)

                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: width * (fillFraction - zeroDbTickFraction))
                        }
                        .frame(height: barHeight)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.white)
                            .frame(width: width * fillFraction)
                    }
                }

                // 0 dB tick mark (visible when overgain is enabled)
                if showTick {
                    Rectangle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 2, height: barHeight + 4)
                        .offset(x: width * zeroDbTickFraction - 1)
                }
            }
        }
    }
}
