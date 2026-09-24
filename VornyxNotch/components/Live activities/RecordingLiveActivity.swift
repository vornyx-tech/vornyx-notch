//
//  RecordingLiveActivity.swift
//  VornyxNotch
//
//  The screen being recorded, either side of the camera.
//

import SwiftUI

/// A red light left of the cut-out, how long it has been recording right of
/// it - built from the music activity's pieces, so it is exactly as wide.
struct RecordingLiveActivity: View {
    @EnvironmentObject var vm: VornyxViewModel
    @ObservedObject private var recorder = ScreenRecordingManager.shared
    @ObservedObject private var preview = BannerPreview.shared

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let since = preview.recording ?? recorder.startedAt

        HStack {
            RecordingDot(size: 9)
                .frame(width: side, height: side)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

            Group {
                if let since {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(VPNLiveActivity.elapsed(from: since, to: context.date))
                    }
                } else {
                    Text("REC")
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.red)
            .fixedSize()
            .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
