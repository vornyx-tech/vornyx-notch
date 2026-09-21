//
//  HelloAnimation.swift
//  VornyxNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/08/24.
//

import SwiftUI

extension ShapeStyle where Self == AngularGradient {
    static var hello: some ShapeStyle {
        LinearGradient(
            stops: [
                .init(color: .blue, location: 0.0),
                .init(color: .purple, location: 0.2),
                .init(color: .red, location: 0.4),
                .init(color: .mint, location: 0.5),
                .init(color: .indigo, location: 0.7),
                .init(color: .pink, location: 0.9),
                .init(color: .blue, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct GlowingSnake<
    Content: Shape,
    Fill: ShapeStyle
>: View, Animatable {
    
    var progress: Double
    var delay: Double = 1.0
    var fill: Fill
    var lineWidth = 4.0
    var blurRadius = 8.0
    
    @ViewBuilder var shape: Content
    
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    
    var body: some View {
        shape
            .trim(
                from: {
                    if progress > 1 - delay {
                        2 * progress - 1.0
                    } else if progress > delay {
                        progress - delay
                    } else {
                        .zero
                    }
                }(),
                to: progress
            )
            .glow(
                fill: fill,
                lineWidth: lineWidth,
                blurRadius: blurRadius
            )
    }
}

/// The first launch: the Vornyx mark traced in light across the opened notch,
/// then filled in white as the glow fades - in place of the handwritten
/// "hello" this used to draw.
struct LogoAnimation: View {
    var onFinish: () -> Void

    @State private var trace = 0.0
    @State private var filled = false
    @State private var glowGone = false

    var body: some View {
        ZStack {
            TracedLogo(progress: trace)
                .opacity(glowGone ? 0 : 1)

            VornyxLogoShape()
                .fill(.white)
                .shadow(color: .white.opacity(filled ? 0.35 : 0), radius: 10)
                .scaleEffect(filled ? 1 : 0.94)
                .opacity(filled ? 1 : 0)
        }
        .task {
            // The notch opening first, so the trace does not start mid-expansion.
            try? await Task.sleep(for: .seconds(0.6))

            withAnimation(.easeInOut(duration: 2.2)) { trace = 1 }
            try? await Task.sleep(for: .seconds(2.0))

            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { filled = true }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) { glowGone = true }
            try? await Task.sleep(for: .seconds(1.6))

            onFinish()
        }
    }
}

/// The mark's outline drawn as far as `progress`, glowing. Animatable itself,
/// so the trim moves smoothly through every frame instead of jumping to the end.
private struct TracedLogo: View, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        VornyxLogoShape()
            .trim(from: 0, to: progress)
            .glow(fill: .hello, lineWidth: 5, blurRadius: 6)
    }
}

extension View where Self: Shape {
    func glow(
        fill: some ShapeStyle,
        lineWidth: Double,
        blurRadius: Double = 8.0,
        lineCap: CGLineCap = .round
    ) -> some View {
        self
            .stroke(style: StrokeStyle(lineWidth: lineWidth / 2, lineCap: lineCap))
            .fill(fill)
            .overlay {
                self
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .fill(fill)
                    .blur(radius: blurRadius)
            }
            .overlay {
                self
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: lineCap))
                    .fill(fill)
                    .blur(radius: blurRadius / 2)
            }
    }
}

#Preview {
    LogoAnimation(onFinish: {})
        .frame(width: 300, height: 100)
        .background(.black)
}

// MARK: - The mark

/// The Vornyx "V", from the logo's own vector file.
///
/// Coordinates are fractions of the mark's bounding box, which is
/// 1.1655 times as wide as it is tall; the mark is fitted inside the rect,
/// centred, without stretching.
struct VornyxLogoShape: Shape {
    static let aspectRatio: CGFloat = 1.1655

    func path(in rect: CGRect) -> Path {
        let width = min(rect.width, rect.height * Self.aspectRatio)
        let height = width / Self.aspectRatio
        let origin = CGPoint(x: rect.midX - width / 2, y: rect.midY - height / 2)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * width, y: origin.y + y * height)
        }

        var path = Path()
        path.move(to: p(0.26423, 0.00030))
        path.addCurve(to: p(0.21011, 0.00126), control1: p(0.23488, 0.00052), control2: p(0.21049, 0.00096))
        path.addCurve(to: p(0.21913, 0.02584), control1: p(0.20808, 0.00274), control2: p(0.20941, 0.00644))
        path.addCurve(to: p(0.23133, 0.05049), control1: p(0.22459, 0.03664), control2: p(0.23006, 0.04775))
        path.addCurve(to: p(0.24327, 0.07433), control1: p(0.23666, 0.06204), control2: p(0.24079, 0.07025))
        path.addCurve(to: p(0.28392, 0.15502), control1: p(0.24435, 0.07618), control2: p(0.26264, 0.11245))
        path.addCurve(to: p(0.40060, 0.38858), control1: p(0.34807, 0.28354), control2: p(0.39590, 0.37918))
        path.addCurve(to: p(0.40746, 0.40228), control1: p(0.40307, 0.39347), control2: p(0.40612, 0.39962))
        path.addCurve(to: p(0.44982, 0.48704), control1: p(0.40879, 0.40495), control2: p(0.42785, 0.44307))
        path.addCurve(to: p(0.49390, 0.57529), control1: p(0.47180, 0.53102), control2: p(0.49162, 0.57070))
        path.addCurve(to: p(0.50171, 0.58447), control1: p(0.49797, 0.58358), control2: p(0.49949, 0.58536))
        path.addCurve(to: p(0.50997, 0.56951), control1: p(0.50235, 0.58417), control2: p(0.50597, 0.57773))
        path.addCurve(to: p(0.52591, 0.53739), control1: p(0.51391, 0.56167), control2: p(0.52109, 0.54716))
        path.addCurve(to: p(0.53817, 0.51259), control1: p(0.53074, 0.52761), control2: p(0.53627, 0.51643))
        path.addCurve(to: p(0.55501, 0.47853), control1: p(0.54681, 0.49511), control2: p(0.55386, 0.48090))
        path.addCurve(to: p(0.57495, 0.43833), control1: p(0.55653, 0.47527), control2: p(0.56955, 0.44907))
        path.addCurve(to: p(0.57774, 0.42493), control1: p(0.57920, 0.42982), control2: p(0.57971, 0.42738))
        path.addCurve(to: p(0.55259, 0.37563), control1: p(0.57679, 0.42367), control2: p(0.56498, 0.40050))
        path.addCurve(to: p(0.53767, 0.34602), control1: p(0.55145, 0.37341), control2: p(0.54478, 0.36008))
        path.addCurve(to: p(0.52274, 0.31641), control1: p(0.53055, 0.33195), control2: p(0.52382, 0.31863))
        path.addCurve(to: p(0.47796, 0.22757), control1: p(0.52064, 0.31226), control2: p(0.50114, 0.27354))
        path.addCurve(to: p(0.44887, 0.16983), control1: p(0.47085, 0.21350), control2: p(0.45776, 0.18752))
        path.addCurve(to: p(0.41902, 0.11060), control1: p(0.43991, 0.15213), control2: p(0.42651, 0.12548))
        path.addCurve(to: p(0.36820, 0.00970), control1: p(0.39291, 0.05885), control2: p(0.37290, 0.01910))
        path.addCurve(to: p(0.36274, 0.00030), control1: p(0.36560, 0.00452), control2: p(0.36319, 0.00030))
        path.addCurve(to: p(0.33981, 0.00015), control1: p(0.36236, 0.00030), control2: p(0.35207, 0.00022))
        path.addCurve(to: p(0.26423, 0.00030), control1: p(0.32762, 0.00000), control2: p(0.29357, 0.00007))
        path.closeSubpath()
        path.move(to: p(0.00165, 0.00296))
        path.addCurve(to: p(0.00191, 0.00859), control1: p(0.00000, 0.00540), control2: p(0.00000, 0.00533))
        path.addCurve(to: p(0.00349, 0.01177), control1: p(0.00279, 0.01007), control2: p(0.00349, 0.01155))
        path.addCurve(to: p(0.00559, 0.01606), control1: p(0.00349, 0.01199), control2: p(0.00445, 0.01392))
        path.addCurve(to: p(0.00953, 0.02399), control1: p(0.00673, 0.01821), control2: p(0.00851, 0.02176))
        path.addCurve(to: p(0.01207, 0.02909), control1: p(0.01054, 0.02621), control2: p(0.01169, 0.02850))
        path.addCurve(to: p(0.01461, 0.03398), control1: p(0.01239, 0.02961), control2: p(0.01359, 0.03183))
        path.addCurve(to: p(0.03258, 0.07018), control1: p(0.01867, 0.04242), control2: p(0.02337, 0.05175))
        path.addCurve(to: p(0.04224, 0.08980), control1: p(0.03792, 0.08069), control2: p(0.04224, 0.08958))
        path.addCurve(to: p(0.04300, 0.09121), control1: p(0.04224, 0.09009), control2: p(0.04256, 0.09069))
        path.addCurve(to: p(0.04573, 0.09609), control1: p(0.04345, 0.09172), control2: p(0.04465, 0.09387))
        path.addCurve(to: p(0.05088, 0.10668), control1: p(0.04675, 0.09831), control2: p(0.04910, 0.10305))
        path.addCurve(to: p(0.05647, 0.11800), control1: p(0.05265, 0.11023), control2: p(0.05513, 0.11534))
        path.addCurve(to: p(0.05939, 0.12393), control1: p(0.05774, 0.12067), control2: p(0.05901, 0.12333))
        path.addCurve(to: p(0.07298, 0.15095), control1: p(0.06028, 0.12556), control2: p(0.07222, 0.14924))
        path.addCurve(to: p(0.07438, 0.15354), control1: p(0.07336, 0.15176), control2: p(0.07400, 0.15295))
        path.addCurve(to: p(0.07749, 0.15983), control1: p(0.07476, 0.15413), control2: p(0.07616, 0.15694))
        path.addCurve(to: p(0.08130, 0.16760), control1: p(0.07882, 0.16264), control2: p(0.08054, 0.16620))
        path.addCurve(to: p(0.08905, 0.18315), control1: p(0.08314, 0.17101), control2: p(0.08753, 0.17989))
        path.addCurve(to: p(0.09127, 0.18759), control1: p(0.08968, 0.18456), control2: p(0.09070, 0.18656))
        path.addCurve(to: p(0.09388, 0.19277), control1: p(0.09184, 0.18863), control2: p(0.09299, 0.19092))
        path.addCurve(to: p(0.10385, 0.21284), control1: p(0.09654, 0.19810), control2: p(0.10144, 0.20802))
        path.addCurve(to: p(0.11338, 0.23179), control1: p(0.10506, 0.21521), control2: p(0.10938, 0.22379))
        path.addCurve(to: p(0.12132, 0.24763), control1: p(0.11738, 0.23978), control2: p(0.12100, 0.24696))
        path.addCurve(to: p(0.12354, 0.25207), control1: p(0.12170, 0.24830), control2: p(0.12265, 0.25030))
        path.addCurve(to: p(0.12576, 0.25659), control1: p(0.12436, 0.25385), control2: p(0.12538, 0.25592))
        path.addCurve(to: p(0.13186, 0.26880), control1: p(0.12671, 0.25844), control2: p(0.13059, 0.26614))
        path.addCurve(to: p(0.13446, 0.27399), control1: p(0.13249, 0.27006), control2: p(0.13364, 0.27243))
        path.addCurve(to: p(0.13688, 0.27902), control1: p(0.13529, 0.27554), control2: p(0.13637, 0.27776))
        path.addCurve(to: p(0.13923, 0.28354), control1: p(0.13739, 0.28020), control2: p(0.13847, 0.28228))
        path.addCurve(to: p(0.14069, 0.28627), control1: p(0.14005, 0.28479), control2: p(0.14069, 0.28605))
        path.addCurve(to: p(0.14405, 0.29323), control1: p(0.14069, 0.28650), control2: p(0.14221, 0.28961))
        path.addCurve(to: p(0.14837, 0.30175), control1: p(0.14596, 0.29679), control2: p(0.14787, 0.30064))
        path.addCurve(to: p(0.15314, 0.31137), control1: p(0.14888, 0.30286), control2: p(0.15104, 0.30715))
        path.addCurve(to: p(0.15835, 0.32174), control1: p(0.15530, 0.31559), control2: p(0.15765, 0.32025))
        path.addCurve(to: p(0.16127, 0.32744), control1: p(0.15911, 0.32322), control2: p(0.16038, 0.32581))
        path.addCurve(to: p(0.16292, 0.33084), control1: p(0.16222, 0.32906), control2: p(0.16292, 0.33062))
        path.addCurve(to: p(0.16514, 0.33521), control1: p(0.16292, 0.33099), control2: p(0.16394, 0.33299))
        path.addCurve(to: p(0.16737, 0.33972), control1: p(0.16635, 0.33743), control2: p(0.16737, 0.33950))
        path.addCurve(to: p(0.16959, 0.34424), control1: p(0.16737, 0.33995), control2: p(0.16838, 0.34202))
        path.addCurve(to: p(0.17181, 0.34868), control1: p(0.17080, 0.34646), control2: p(0.17181, 0.34846))
        path.addCurve(to: p(0.17391, 0.35290), control1: p(0.17181, 0.34890), control2: p(0.17276, 0.35076))
        path.addCurve(to: p(0.17785, 0.36082), control1: p(0.17505, 0.35505), control2: p(0.17683, 0.35860))
        path.addCurve(to: p(0.18039, 0.36593), control1: p(0.17886, 0.36304), control2: p(0.18001, 0.36534))
        path.addCurve(to: p(0.18763, 0.38059), control1: p(0.18102, 0.36697), control2: p(0.18267, 0.37030))
        path.addCurve(to: p(0.19118, 0.38747), control1: p(0.18915, 0.38377), control2: p(0.19080, 0.38688))
        path.addCurve(to: p(0.19404, 0.39303), control1: p(0.19163, 0.38807), control2: p(0.19290, 0.39058))
        path.addCurve(to: p(0.20338, 0.41176), control1: p(0.19519, 0.39547), control2: p(0.19938, 0.40391))
        path.addCurve(to: p(0.21056, 0.42664), control1: p(0.20732, 0.41960), control2: p(0.21056, 0.42634))
        path.addCurve(to: p(0.21132, 0.42804), control1: p(0.21056, 0.42693), control2: p(0.21087, 0.42752))
        path.addCurve(to: p(0.21405, 0.43293), control1: p(0.21176, 0.42856), control2: p(0.21297, 0.43071))
        path.addCurve(to: p(0.21919, 0.44351), control1: p(0.21507, 0.43515), control2: p(0.21742, 0.43989))
        path.addCurve(to: p(0.22478, 0.45484), control1: p(0.22097, 0.44707), control2: p(0.22345, 0.45218))
        path.addCurve(to: p(0.22771, 0.46076), control1: p(0.22605, 0.45751), control2: p(0.22732, 0.46017))
        path.addCurve(to: p(0.23711, 0.47942), control1: p(0.22872, 0.46269), control2: p(0.23577, 0.47653))
        path.addCurve(to: p(0.24003, 0.48512), control1: p(0.23787, 0.48090), control2: p(0.23914, 0.48349))
        path.addCurve(to: p(0.24168, 0.48867), control1: p(0.24098, 0.48675), control2: p(0.24168, 0.48838))
        path.addCurve(to: p(0.24257, 0.49030), control1: p(0.24168, 0.48890), control2: p(0.24206, 0.48971))
        path.addCurve(to: p(0.24581, 0.49667), control1: p(0.24301, 0.49097), control2: p(0.24447, 0.49378))
        path.addCurve(to: p(0.24962, 0.50444), control1: p(0.24714, 0.49948), control2: p(0.24886, 0.50304))
        path.addCurve(to: p(0.25718, 0.51962), control1: p(0.25210, 0.50911), control2: p(0.25546, 0.51584))
        path.addCurve(to: p(0.26239, 0.52998), control1: p(0.25813, 0.52162), control2: p(0.26048, 0.52628))
        path.addCurve(to: p(0.26759, 0.54035), control1: p(0.26435, 0.53361), control2: p(0.26664, 0.53827))
        path.addCurve(to: p(0.26994, 0.54508), control1: p(0.26848, 0.54235), control2: p(0.26956, 0.54449))
        path.addCurve(to: p(0.27248, 0.55004), control1: p(0.27026, 0.54560), control2: p(0.27147, 0.54790))
        path.addCurve(to: p(0.28709, 0.57936), control1: p(0.27356, 0.55227), control2: p(0.28011, 0.56544))
        path.addCurve(to: p(0.30005, 0.60542), control1: p(0.29408, 0.59328), control2: p(0.29992, 0.60497))
        path.addCurve(to: p(0.30107, 0.60734), control1: p(0.30018, 0.60586), control2: p(0.30062, 0.60675))
        path.addCurve(to: p(0.30405, 0.61327), control1: p(0.30151, 0.60794), control2: p(0.30285, 0.61060))
        path.addCurve(to: p(0.30780, 0.62104), control1: p(0.30520, 0.61593), control2: p(0.30691, 0.61941))
        path.addCurve(to: p(0.31606, 0.63747), control1: p(0.30932, 0.62385), control2: p(0.31263, 0.63037))
        path.addCurve(to: p(0.32368, 0.65265), control1: p(0.31688, 0.63910), control2: p(0.32031, 0.64599))
        path.addCurve(to: p(0.33111, 0.66746), control1: p(0.32705, 0.65924), control2: p(0.33041, 0.66598))
        path.addCurve(to: p(0.33403, 0.67316), control1: p(0.33187, 0.66894), control2: p(0.33314, 0.67153))
        path.addCurve(to: p(0.33568, 0.67656), control1: p(0.33498, 0.67479), control2: p(0.33568, 0.67634))
        path.addCurve(to: p(0.33791, 0.68108), control1: p(0.33568, 0.67678), control2: p(0.33670, 0.67886))
        path.addCurve(to: p(0.34013, 0.68552), control1: p(0.33911, 0.68330), control2: p(0.34013, 0.68530))
        path.addCurve(to: p(0.34223, 0.68974), control1: p(0.34013, 0.68574), control2: p(0.34108, 0.68759))
        path.addCurve(to: p(0.34616, 0.69766), control1: p(0.34337, 0.69189), control2: p(0.34515, 0.69544))
        path.addCurve(to: p(0.34870, 0.70277), control1: p(0.34718, 0.69988), control2: p(0.34832, 0.70218))
        path.addCurve(to: p(0.35595, 0.71743), control1: p(0.34934, 0.70381), control2: p(0.35099, 0.70714))
        path.addCurve(to: p(0.35950, 0.72431), control1: p(0.35747, 0.72061), control2: p(0.35912, 0.72372))
        path.addCurve(to: p(0.36185, 0.72875), control1: p(0.35995, 0.72490), control2: p(0.36103, 0.72690))
        path.addCurve(to: p(0.36681, 0.73875), control1: p(0.36274, 0.73060), control2: p(0.36496, 0.73505))
        path.addCurve(to: p(0.37138, 0.74800), control1: p(0.36865, 0.74237), control2: p(0.37068, 0.74659))
        path.addCurve(to: p(0.37576, 0.75674), control1: p(0.37208, 0.74941), control2: p(0.37405, 0.75333))
        path.addCurve(to: p(0.37887, 0.76340), control1: p(0.37748, 0.76007), control2: p(0.37887, 0.76310))
        path.addCurve(to: p(0.37964, 0.76488), control1: p(0.37887, 0.76377), control2: p(0.37919, 0.76436))
        path.addCurve(to: p(0.38237, 0.76977), control1: p(0.38008, 0.76540), control2: p(0.38129, 0.76755))
        path.addCurve(to: p(0.39755, 0.79272), control1: p(0.39425, 0.79434), control2: p(0.39418, 0.79420))
        path.addCurve(to: p(0.39856, 0.79116), control1: p(0.39812, 0.79249), control2: p(0.39856, 0.79175))
        path.addCurve(to: p(0.40809, 0.77021), control1: p(0.39856, 0.78975), control2: p(0.40415, 0.77739))
        path.addCurve(to: p(0.41101, 0.76429), control1: p(0.40847, 0.76962), control2: p(0.40974, 0.76695))
        path.addCurve(to: p(0.41660, 0.75296), control1: p(0.41235, 0.76162), control2: p(0.41482, 0.75651))
        path.addCurve(to: p(0.42175, 0.74245), control1: p(0.41838, 0.74933), control2: p(0.42073, 0.74467))
        path.addCurve(to: p(0.42429, 0.73756), control1: p(0.42283, 0.74030), control2: p(0.42397, 0.73808))
        path.addCurve(to: p(0.42683, 0.73245), control1: p(0.42467, 0.73697), control2: p(0.42581, 0.73468))
        path.addCurve(to: p(0.42969, 0.72653), control1: p(0.42778, 0.73023), control2: p(0.42912, 0.72757))
        path.addCurve(to: p(0.43343, 0.71913), control1: p(0.43026, 0.72550), control2: p(0.43197, 0.72216))
        path.addCurve(to: p(0.44588, 0.69396), control1: p(0.43934, 0.70684), control2: p(0.44385, 0.69773))
        path.addCurve(to: p(0.44970, 0.68619), control1: p(0.44665, 0.69255), control2: p(0.44836, 0.68900))
        path.addCurve(to: p(0.45281, 0.67989), control1: p(0.45103, 0.68330), control2: p(0.45243, 0.68049))
        path.addCurve(to: p(0.45446, 0.67656), control1: p(0.45325, 0.67930), control2: p(0.45395, 0.67775))
        path.addCurve(to: p(0.45744, 0.67042), control1: p(0.45497, 0.67530), control2: p(0.45630, 0.67256))
        path.addCurve(to: p(0.45954, 0.66627), control1: p(0.45859, 0.66827), control2: p(0.45954, 0.66642))
        path.addCurve(to: p(0.46335, 0.65842), control1: p(0.45954, 0.66605), control2: p(0.46126, 0.66257))
        path.addCurve(to: p(0.46716, 0.65058), control1: p(0.46545, 0.65428), control2: p(0.46716, 0.65080))
        path.addCurve(to: p(0.47231, 0.64140), control1: p(0.46716, 0.65006), control2: p(0.47180, 0.64177))
        path.addCurve(to: p(0.47326, 0.63873), control1: p(0.47262, 0.64110), control2: p(0.47301, 0.63992))
        path.addCurve(to: p(0.47180, 0.63399), control1: p(0.47358, 0.63696), control2: p(0.47326, 0.63599))
        path.addCurve(to: p(0.46811, 0.62763), control1: p(0.47085, 0.63266), control2: p(0.46919, 0.62977))
        path.addCurve(to: p(0.46202, 0.61534), control1: p(0.46710, 0.62541), control2: p(0.46430, 0.61993))
        path.addCurve(to: p(0.45103, 0.59350), control1: p(0.45636, 0.60409), control2: p(0.45605, 0.60349))
        path.addCurve(to: p(0.44131, 0.57403), control1: p(0.44862, 0.58869), control2: p(0.44423, 0.57995))
        path.addCurve(to: p(0.43540, 0.56219), control1: p(0.43839, 0.56811), control2: p(0.43572, 0.56278))
        path.addCurve(to: p(0.42962, 0.55056), control1: p(0.43471, 0.56078), control2: p(0.43115, 0.55367))
        path.addCurve(to: p(0.42689, 0.54523), control1: p(0.42899, 0.54930), control2: p(0.42778, 0.54686))
        path.addCurve(to: p(0.42524, 0.54168), control1: p(0.42594, 0.54360), control2: p(0.42524, 0.54198))
        path.addCurve(to: p(0.42435, 0.54005), control1: p(0.42524, 0.54146), control2: p(0.42486, 0.54064))
        path.addCurve(to: p(0.42130, 0.53405), control1: p(0.42384, 0.53938), control2: p(0.42251, 0.53672))
        path.addCurve(to: p(0.41756, 0.52628), control1: p(0.42016, 0.53139), control2: p(0.41845, 0.52791))
        path.addCurve(to: p(0.40993, 0.51110), control1: p(0.41533, 0.52228), control2: p(0.41178, 0.51518))
        path.addCurve(to: p(0.40803, 0.50740), control1: p(0.40911, 0.50925), control2: p(0.40828, 0.50763))
        path.addCurve(to: p(0.39869, 0.48875), control1: p(0.40771, 0.50703), control2: p(0.40168, 0.49497))
        path.addCurve(to: p(0.39577, 0.48305), control1: p(0.39793, 0.48727), control2: p(0.39666, 0.48468))
        path.addCurve(to: p(0.39412, 0.47964), control1: p(0.39482, 0.48142), control2: p(0.39412, 0.47986))
        path.addCurve(to: p(0.39190, 0.47527), control1: p(0.39412, 0.47949), control2: p(0.39310, 0.47749))
        path.addCurve(to: p(0.38967, 0.47076), control1: p(0.39069, 0.47305), control2: p(0.38967, 0.47098))
        path.addCurve(to: p(0.38745, 0.46624), control1: p(0.38967, 0.47054), control2: p(0.38866, 0.46846))
        path.addCurve(to: p(0.38523, 0.46180), control1: p(0.38624, 0.46402), control2: p(0.38523, 0.46202))
        path.addCurve(to: p(0.38313, 0.45758), control1: p(0.38523, 0.46158), control2: p(0.38427, 0.45973))
        path.addCurve(to: p(0.37919, 0.44966), control1: p(0.38199, 0.45543), control2: p(0.38021, 0.45188))
        path.addCurve(to: p(0.37659, 0.44448), control1: p(0.37818, 0.44744), control2: p(0.37703, 0.44507))
        path.addCurve(to: p(0.37417, 0.43967), control1: p(0.37621, 0.44389), control2: p(0.37506, 0.44166))
        path.addCurve(to: p(0.36992, 0.43123), control1: p(0.37322, 0.43759), control2: p(0.37132, 0.43382))
        path.addCurve(to: p(0.36744, 0.42619), control1: p(0.36858, 0.42871), control2: p(0.36744, 0.42641))
        path.addCurve(to: p(0.36522, 0.42182), control1: p(0.36744, 0.42597), control2: p(0.36643, 0.42397))
        path.addCurve(to: p(0.36300, 0.41753), control1: p(0.36401, 0.41968), control2: p(0.36300, 0.41775))
        path.addCurve(to: p(0.36077, 0.41309), control1: p(0.36300, 0.41731), control2: p(0.36198, 0.41531))
        path.addCurve(to: p(0.35855, 0.40865), control1: p(0.35957, 0.41087), control2: p(0.35855, 0.40887))
        path.addCurve(to: p(0.35474, 0.40080), control1: p(0.35855, 0.40850), control2: p(0.35683, 0.40495))
        path.addCurve(to: p(0.35093, 0.39280), control1: p(0.35264, 0.39665), control2: p(0.35093, 0.39310))
        path.addCurve(to: p(0.35004, 0.39125), control1: p(0.35093, 0.39258), control2: p(0.35055, 0.39184))
        path.addCurve(to: p(0.34769, 0.38673), control1: p(0.34959, 0.39058), control2: p(0.34851, 0.38858))
        path.addCurve(to: p(0.34546, 0.38229), control1: p(0.34686, 0.38488), control2: p(0.34591, 0.38288))
        path.addCurve(to: p(0.34235, 0.37600), control1: p(0.34508, 0.38170), control2: p(0.34369, 0.37881))
        path.addCurve(to: p(0.33854, 0.36823), control1: p(0.34102, 0.37311), control2: p(0.33930, 0.36963))
        path.addCurve(to: p(0.33054, 0.35216), control1: p(0.33721, 0.36571), control2: p(0.33352, 0.35838))
        path.addCurve(to: p(0.32495, 0.34106), control1: p(0.32971, 0.35053), control2: p(0.32717, 0.34550))
        path.addCurve(to: p(0.32019, 0.33158), control1: p(0.32266, 0.33669), control2: p(0.32057, 0.33240))
        path.addCurve(to: p(0.31879, 0.32899), control1: p(0.31980, 0.33077), control2: p(0.31917, 0.32958))
        path.addCurve(to: p(0.31657, 0.32455), control1: p(0.31841, 0.32840), control2: p(0.31739, 0.32640))
        path.addCurve(to: p(0.31434, 0.32011), control1: p(0.31574, 0.32270), control2: p(0.31472, 0.32070))
        path.addCurve(to: p(0.31155, 0.31455), control1: p(0.31396, 0.31951), control2: p(0.31269, 0.31700))
        path.addCurve(to: p(0.30723, 0.30567), control1: p(0.31047, 0.31211), control2: p(0.30850, 0.30811))
        path.addCurve(to: p(0.30265, 0.29679), control1: p(0.30596, 0.30323), control2: p(0.30393, 0.29923))
        path.addCurve(to: p(0.29948, 0.29012), control1: p(0.30145, 0.29434), control2: p(0.29999, 0.29131))
        path.addCurve(to: p(0.29713, 0.28561), control1: p(0.29897, 0.28887), control2: p(0.29789, 0.28687))
        path.addCurve(to: p(0.29567, 0.28280), control1: p(0.29630, 0.28435), control2: p(0.29567, 0.28309))
        path.addCurve(to: p(0.29319, 0.27769), control1: p(0.29567, 0.28257), control2: p(0.29459, 0.28020))
        path.addCurve(to: p(0.28894, 0.26925), control1: p(0.29186, 0.27517), control2: p(0.28995, 0.27139))
        path.addCurve(to: p(0.28322, 0.25777), control1: p(0.28792, 0.26710), control2: p(0.28532, 0.26199))
        path.addCurve(to: p(0.27801, 0.24756), control1: p(0.28106, 0.25355), control2: p(0.27871, 0.24896))
        path.addCurve(to: p(0.26753, 0.22631), control1: p(0.27642, 0.24423), control2: p(0.27350, 0.23838))
        path.addCurve(to: p(0.26143, 0.21395), control1: p(0.26486, 0.22098), control2: p(0.26213, 0.21543))
        path.addCurve(to: p(0.25857, 0.20840), control1: p(0.26073, 0.21254), control2: p(0.25946, 0.21002))
        path.addCurve(to: p(0.25692, 0.20484), control1: p(0.25762, 0.20677), control2: p(0.25692, 0.20514))
        path.addCurve(to: p(0.25603, 0.20321), control1: p(0.25692, 0.20462), control2: p(0.25654, 0.20381))
        path.addCurve(to: p(0.25279, 0.19685), control1: p(0.25559, 0.20255), control2: p(0.25413, 0.19966))
        path.addCurve(to: p(0.24898, 0.18907), control1: p(0.25146, 0.19396), control2: p(0.24975, 0.19048))
        path.addCurve(to: p(0.24162, 0.17427), control1: p(0.24682, 0.18500), control2: p(0.24327, 0.17789))
        path.addCurve(to: p(0.23971, 0.17057), control1: p(0.24079, 0.17242), control2: p(0.23996, 0.17079))
        path.addCurve(to: p(0.23037, 0.15191), control1: p(0.23939, 0.17020), control2: p(0.23336, 0.15813))
        path.addCurve(to: p(0.22745, 0.14621), control1: p(0.22961, 0.15043), control2: p(0.22834, 0.14784))
        path.addCurve(to: p(0.22580, 0.14266), control1: p(0.22650, 0.14458), control2: p(0.22580, 0.14295))
        path.addCurve(to: p(0.22491, 0.14103), control1: p(0.22580, 0.14243), control2: p(0.22542, 0.14162))
        path.addCurve(to: p(0.22167, 0.13466), control1: p(0.22447, 0.14036), control2: p(0.22301, 0.13747))
        path.addCurve(to: p(0.21811, 0.12748), control1: p(0.22034, 0.13177), control2: p(0.21875, 0.12859))
        path.addCurve(to: p(0.21691, 0.12504), control1: p(0.21742, 0.12644), control2: p(0.21691, 0.12533))
        path.addCurve(to: p(0.21475, 0.12060), control1: p(0.21691, 0.12481), control2: p(0.21596, 0.12282))
        path.addCurve(to: p(0.21056, 0.11230), control1: p(0.21354, 0.11845), control2: p(0.21164, 0.11467))
        path.addCurve(to: p(0.20382, 0.09890), control1: p(0.20948, 0.10993), control2: p(0.20643, 0.10386))
        path.addCurve(to: p(0.19912, 0.08935), control1: p(0.20122, 0.09387), control2: p(0.19912, 0.08958))
        path.addCurve(to: p(0.19690, 0.08499), control1: p(0.19912, 0.08913), control2: p(0.19811, 0.08713))
        path.addCurve(to: p(0.19468, 0.08069), control1: p(0.19569, 0.08284), control2: p(0.19468, 0.08092))
        path.addCurve(to: p(0.19245, 0.07625), control1: p(0.19468, 0.08047), control2: p(0.19366, 0.07847))
        path.addCurve(to: p(0.19023, 0.07181), control1: p(0.19125, 0.07403), control2: p(0.19023, 0.07203))
        path.addCurve(to: p(0.18642, 0.06396), control1: p(0.19023, 0.07166), control2: p(0.18852, 0.06811))
        path.addCurve(to: p(0.18261, 0.05597), control1: p(0.18432, 0.05982), control2: p(0.18261, 0.05626))
        path.addCurve(to: p(0.18172, 0.05441), control1: p(0.18261, 0.05574), control2: p(0.18223, 0.05500))
        path.addCurve(to: p(0.17937, 0.04990), control1: p(0.18128, 0.05375), control2: p(0.18020, 0.05175))
        path.addCurve(to: p(0.17715, 0.04545), control1: p(0.17854, 0.04805), control2: p(0.17753, 0.04605))
        path.addCurve(to: p(0.17435, 0.03990), control1: p(0.17677, 0.04486), control2: p(0.17550, 0.04235))
        path.addCurve(to: p(0.16673, 0.02473), control1: p(0.17207, 0.03494), control2: p(0.16838, 0.02754))
        path.addCurve(to: p(0.16355, 0.01806), control1: p(0.16616, 0.02369), control2: p(0.16470, 0.02073))
        path.addCurve(to: p(0.15987, 0.01088), control1: p(0.16235, 0.01540), control2: p(0.16070, 0.01221))
        path.addCurve(to: p(0.15727, 0.00496), control1: p(0.15904, 0.00955), control2: p(0.15790, 0.00688))
        path.addLine(to: p(0.15619, 0.00141))
        path.addLine(to: p(0.07959, 0.00118))
        path.addLine(to: p(0.00299, 0.00104))
        path.addLine(to: p(0.00165, 0.00296))
        path.closeSubpath()
        path.move(to: p(0.63129, 0.00244))
        path.addCurve(to: p(0.62614, 0.01110), control1: p(0.62989, 0.00341), control2: p(0.62837, 0.00600))
        path.addCurve(to: p(0.61941, 0.02561), control1: p(0.62443, 0.01518), control2: p(0.62138, 0.02169))
        path.addCurve(to: p(0.61369, 0.03746), control1: p(0.61744, 0.02954), control2: p(0.61490, 0.03487))
        path.addCurve(to: p(0.60912, 0.04694), control1: p(0.61249, 0.04005), control2: p(0.61045, 0.04427))
        path.addCurve(to: p(0.60518, 0.05493), control1: p(0.60779, 0.04960), control2: p(0.60601, 0.05323))
        path.addCurve(to: p(0.60182, 0.06159), control1: p(0.60429, 0.05671), control2: p(0.60277, 0.05974))
        path.addCurve(to: p(0.59889, 0.06766), control1: p(0.60080, 0.06352), control2: p(0.59947, 0.06626))
        path.addCurve(to: p(0.59566, 0.07418), control1: p(0.59826, 0.06907), control2: p(0.59680, 0.07203))
        path.addCurve(to: p(0.59356, 0.07832), control1: p(0.59451, 0.07633), control2: p(0.59356, 0.07818))
        path.addCurve(to: p(0.58975, 0.08617), control1: p(0.59356, 0.07855), control2: p(0.59184, 0.08203))
        path.addCurve(to: p(0.58594, 0.09402), control1: p(0.58765, 0.09032), control2: p(0.58594, 0.09380))
        path.addCurve(to: p(0.58371, 0.09831), control1: p(0.58594, 0.09417), control2: p(0.58492, 0.09609))
        path.addCurve(to: p(0.58149, 0.10283), control1: p(0.58251, 0.10053), control2: p(0.58149, 0.10261))
        path.addCurve(to: p(0.57984, 0.10623), control1: p(0.58149, 0.10305), control2: p(0.58079, 0.10460))
        path.addCurve(to: p(0.57698, 0.11179), control1: p(0.57895, 0.10786), control2: p(0.57768, 0.11038))
        path.addCurve(to: p(0.57088, 0.12415), control1: p(0.57628, 0.11327), control2: p(0.57355, 0.11882))
        path.addCurve(to: p(0.56415, 0.13799), control1: p(0.56822, 0.12955), control2: p(0.56523, 0.13577))
        path.addCurve(to: p(0.56142, 0.14325), control1: p(0.56314, 0.14021), control2: p(0.56186, 0.14258))
        path.addCurve(to: p(0.56053, 0.14480), control1: p(0.56091, 0.14384), control2: p(0.56053, 0.14458))
        path.addCurve(to: p(0.54224, 0.18204), control1: p(0.56053, 0.14517), control2: p(0.54980, 0.16694))
        path.addCurve(to: p(0.53690, 0.19277), control1: p(0.54103, 0.18448), control2: p(0.53862, 0.18930))
        path.addCurve(to: p(0.53322, 0.20018), control1: p(0.53519, 0.19625), control2: p(0.53354, 0.19959))
        path.addCurve(to: p(0.53030, 0.20610), control1: p(0.53284, 0.20077), control2: p(0.53157, 0.20344))
        path.addCurve(to: p(0.52471, 0.21743), control1: p(0.52896, 0.20877), control2: p(0.52649, 0.21387))
        path.addCurve(to: p(0.51994, 0.22705), control1: p(0.52293, 0.22105), control2: p(0.52077, 0.22542))
        path.addCurve(to: p(0.51563, 0.23571), control1: p(0.51912, 0.22875), control2: p(0.51721, 0.23268))
        path.addCurve(to: p(0.51232, 0.24237), control1: p(0.51410, 0.23875), control2: p(0.51258, 0.24178))
        path.addCurve(to: p(0.51010, 0.25229), control1: p(0.50877, 0.25000), control2: p(0.50845, 0.25155))
        path.addCurve(to: p(0.61458, 0.25274), control1: p(0.51067, 0.25252), control2: p(0.55767, 0.25274))
        path.addCurve(to: p(0.71805, 0.25378), control1: p(0.70192, 0.25274), control2: p(0.71805, 0.25289))
        path.addCurve(to: p(0.71443, 0.26192), control1: p(0.71805, 0.25429), control2: p(0.71640, 0.25800))
        path.addCurve(to: p(0.70821, 0.27450), control1: p(0.71240, 0.26584), control2: p(0.70960, 0.27154))
        path.addCurve(to: p(0.70497, 0.28094), control1: p(0.70681, 0.27747), control2: p(0.70535, 0.28043))
        path.addCurve(to: p(0.70249, 0.28605), control1: p(0.70452, 0.28154), control2: p(0.70344, 0.28383))
        path.addCurve(to: p(0.69963, 0.29198), control1: p(0.70154, 0.28827), control2: p(0.70027, 0.29094))
        path.addCurve(to: p(0.69614, 0.29901), control1: p(0.69906, 0.29301), control2: p(0.69747, 0.29612))
        path.addCurve(to: p(0.69303, 0.30530), control1: p(0.69480, 0.30182), control2: p(0.69341, 0.30471))
        path.addCurve(to: p(0.69080, 0.30974), control1: p(0.69258, 0.30589), control2: p(0.69163, 0.30789))
        path.addCurve(to: p(0.68858, 0.31418), control1: p(0.68998, 0.31159), control2: p(0.68896, 0.31359))
        path.addCurve(to: p(0.68598, 0.31937), control1: p(0.68814, 0.31478), control2: p(0.68699, 0.31715))
        path.addCurve(to: p(0.68312, 0.32529), control1: p(0.68502, 0.32159), control2: p(0.68369, 0.32425))
        path.addCurve(to: p(0.67962, 0.33232), control1: p(0.68248, 0.32633), control2: p(0.68096, 0.32943))
        path.addCurve(to: p(0.67651, 0.33861), control1: p(0.67829, 0.33513), control2: p(0.67689, 0.33802))
        path.addCurve(to: p(0.67429, 0.34306), control1: p(0.67607, 0.33921), control2: p(0.67511, 0.34121))
        path.addCurve(to: p(0.66692, 0.35786), control1: p(0.67270, 0.34661), control2: p(0.66921, 0.35357))
        path.addCurve(to: p(0.66311, 0.36564), control1: p(0.66616, 0.35927), control2: p(0.66444, 0.36275))
        path.addCurve(to: p(0.66000, 0.37193), control1: p(0.66178, 0.36845), control2: p(0.66038, 0.37134))
        path.addCurve(to: p(0.65739, 0.37711), control1: p(0.65955, 0.37252), control2: p(0.65841, 0.37489))
        path.addCurve(to: p(0.65454, 0.38303), control1: p(0.65644, 0.37933), control2: p(0.65511, 0.38200))
        path.addCurve(to: p(0.65079, 0.39044), control1: p(0.65396, 0.38407), control2: p(0.65225, 0.38740))
        path.addCurve(to: p(0.64386, 0.40450), control1: p(0.64647, 0.39947), control2: p(0.64494, 0.40258))
        path.addCurve(to: p(0.64101, 0.41035), control1: p(0.64329, 0.40554), control2: p(0.64202, 0.40813))
        path.addCurve(to: p(0.63796, 0.41642), control1: p(0.63999, 0.41257), control2: p(0.63866, 0.41531))
        path.addCurve(to: p(0.63675, 0.41879), control1: p(0.63732, 0.41753), control2: p(0.63675, 0.41857))
        path.addCurve(to: p(0.63072, 0.43115), control1: p(0.63675, 0.41901), control2: p(0.63402, 0.42456))
        path.addCurve(to: p(0.62468, 0.44344), control1: p(0.62741, 0.43774), control2: p(0.62468, 0.44329))
        path.addCurve(to: p(0.62303, 0.44677), control1: p(0.62468, 0.44366), control2: p(0.62398, 0.44514))
        path.addCurve(to: p(0.62017, 0.45232), control1: p(0.62214, 0.44840), control2: p(0.62087, 0.45092))
        path.addCurve(to: p(0.61408, 0.46469), control1: p(0.61947, 0.45381), control2: p(0.61674, 0.45936))
        path.addCurve(to: p(0.60785, 0.47742), control1: p(0.61141, 0.47009), control2: p(0.60861, 0.47579))
        path.addCurve(to: p(0.60302, 0.48704), control1: p(0.60702, 0.47905), control2: p(0.60487, 0.48334))
        path.addCurve(to: p(0.59661, 0.50000), control1: p(0.60124, 0.49067), control2: p(0.59832, 0.49652))
        path.addCurve(to: p(0.59292, 0.50740), control1: p(0.59489, 0.50348), control2: p(0.59324, 0.50681))
        path.addCurve(to: p(0.59000, 0.51333), control1: p(0.59254, 0.50800), control2: p(0.59127, 0.51066))
        path.addCurve(to: p(0.58441, 0.52465), control1: p(0.58867, 0.51599), control2: p(0.58619, 0.52110))
        path.addCurve(to: p(0.57927, 0.53516), control1: p(0.58263, 0.52828), control2: p(0.58035, 0.53294))
        path.addCurve(to: p(0.57673, 0.54005), control1: p(0.57825, 0.53731), control2: p(0.57705, 0.53953))
        path.addCurve(to: p(0.57419, 0.54516), control1: p(0.57635, 0.54064), control2: p(0.57520, 0.54294))
        path.addCurve(to: p(0.57133, 0.55108), control1: p(0.57323, 0.54738), control2: p(0.57190, 0.55004))
        path.addCurve(to: p(0.56758, 0.55848), control1: p(0.57076, 0.55212), control2: p(0.56904, 0.55545))
        path.addCurve(to: p(0.55481, 0.58439), control1: p(0.56225, 0.56966), control2: p(0.55786, 0.57847))
        path.addCurve(to: p(0.54637, 0.60164), control1: p(0.55272, 0.58839), control2: p(0.54884, 0.59639))
        path.addCurve(to: p(0.54300, 0.60823), control1: p(0.54541, 0.60379), control2: p(0.54389, 0.60675))
        path.addCurve(to: p(0.54148, 0.61134), control1: p(0.54217, 0.60979), control2: p(0.54148, 0.61119))
        path.addCurve(to: p(0.53767, 0.61919), control1: p(0.54148, 0.61149), control2: p(0.53976, 0.61504))
        path.addCurve(to: p(0.53385, 0.62704), control1: p(0.53557, 0.62333), control2: p(0.53385, 0.62681))
        path.addCurve(to: p(0.53163, 0.63133), control1: p(0.53385, 0.62718), control2: p(0.53284, 0.62911))
        path.addCurve(to: p(0.52941, 0.63585), control1: p(0.53042, 0.63355), control2: p(0.52941, 0.63562))
        path.addCurve(to: p(0.52718, 0.64036), control1: p(0.52941, 0.63607), control2: p(0.52839, 0.63814))
        path.addCurve(to: p(0.52496, 0.64466), control1: p(0.52598, 0.64258), control2: p(0.52496, 0.64451))
        path.addCurve(to: p(0.52210, 0.65058), control1: p(0.52496, 0.64488), control2: p(0.52369, 0.64747))
        path.addCurve(to: p(0.51696, 0.66116), control1: p(0.52058, 0.65369), control2: p(0.51823, 0.65842))
        path.addCurve(to: p(0.51391, 0.66731), control1: p(0.51569, 0.66398), control2: p(0.51429, 0.66672))
        path.addCurve(to: p(0.51169, 0.67175), control1: p(0.51347, 0.66790), control2: p(0.51251, 0.66990))
        path.addCurve(to: p(0.50934, 0.67627), control1: p(0.51086, 0.67360), control2: p(0.50978, 0.67560))
        path.addCurve(to: p(0.50845, 0.67782), control1: p(0.50883, 0.67686), control2: p(0.50845, 0.67760))
        path.addCurve(to: p(0.50559, 0.68389), control1: p(0.50845, 0.67812), control2: p(0.50718, 0.68078))
        path.addCurve(to: p(0.50044, 0.69448), control1: p(0.50407, 0.68700), control2: p(0.50171, 0.69174))
        path.addCurve(to: p(0.49727, 0.70070), control1: p(0.49917, 0.69729), control2: p(0.49771, 0.70003))
        path.addCurve(to: p(0.49638, 0.70232), control1: p(0.49676, 0.70129), control2: p(0.49638, 0.70203))
        path.addCurve(to: p(0.49130, 0.71291), control1: p(0.49638, 0.70255), control2: p(0.49409, 0.70728))
        path.addCurve(to: p(0.48622, 0.72320), control1: p(0.48850, 0.71846), control2: p(0.48622, 0.72313))
        path.addCurve(to: p(0.48374, 0.72809), control1: p(0.48622, 0.72335), control2: p(0.48507, 0.72557))
        path.addCurve(to: p(0.47917, 0.73727), control1: p(0.48234, 0.73068), control2: p(0.48031, 0.73482))
        path.addCurve(to: p(0.47612, 0.74356), control1: p(0.47809, 0.73971), control2: p(0.47669, 0.74252))
        path.addCurve(to: p(0.47008, 0.75540), control1: p(0.47548, 0.74460), control2: p(0.47282, 0.74993))
        path.addCurve(to: p(0.46462, 0.76651), control1: p(0.46742, 0.76088), control2: p(0.46494, 0.76592))
        path.addCurve(to: p(0.46170, 0.77243), control1: p(0.46424, 0.76710), control2: p(0.46297, 0.76977))
        path.addCurve(to: p(0.45611, 0.78376), control1: p(0.46037, 0.77510), control2: p(0.45789, 0.78020))
        path.addCurve(to: p(0.45109, 0.79412), control1: p(0.45433, 0.78739), control2: p(0.45205, 0.79205))
        path.addCurve(to: p(0.44773, 0.80071), control1: p(0.45014, 0.79627), control2: p(0.44862, 0.79923))
        path.addCurve(to: p(0.44620, 0.80389), control1: p(0.44690, 0.80227), control2: p(0.44620, 0.80367))
        path.addCurve(to: p(0.44455, 0.80730), control1: p(0.44620, 0.80412), control2: p(0.44544, 0.80567))
        path.addCurve(to: p(0.43839, 0.81981), control1: p(0.44309, 0.81004), control2: p(0.44220, 0.81182))
        path.addCurve(to: p(0.43667, 0.82314), control1: p(0.43775, 0.82122), control2: p(0.43693, 0.82270))
        path.addCurve(to: p(0.43382, 0.82906), control1: p(0.43642, 0.82351), control2: p(0.43515, 0.82618))
        path.addCurve(to: p(0.43083, 0.83506), control1: p(0.43248, 0.83188), control2: p(0.43115, 0.83462))
        path.addCurve(to: p(0.42524, 0.84876), control1: p(0.42943, 0.83721), control2: p(0.42524, 0.84742))
        path.addCurve(to: p(0.43032, 0.86023), control1: p(0.42524, 0.84957), control2: p(0.42753, 0.85475))
        path.addCurve(to: p(0.43540, 0.87067), control1: p(0.43312, 0.86578), control2: p(0.43540, 0.87045))
        path.addCurve(to: p(0.43629, 0.87230), control1: p(0.43540, 0.87097), control2: p(0.43579, 0.87171))
        path.addCurve(to: p(0.43890, 0.87718), control1: p(0.43680, 0.87296), control2: p(0.43794, 0.87511))
        path.addCurve(to: p(0.44239, 0.88436), control1: p(0.43979, 0.87918), control2: p(0.44137, 0.88244))
        path.addCurve(to: p(0.44576, 0.89110), control1: p(0.44334, 0.88622), control2: p(0.44493, 0.88925))
        path.addCurve(to: p(0.44900, 0.89747), control1: p(0.44665, 0.89295), control2: p(0.44811, 0.89577))
        path.addCurve(to: p(0.45065, 0.90102), control1: p(0.44989, 0.89910), control2: p(0.45065, 0.90073))
        path.addCurve(to: p(0.45154, 0.90265), control1: p(0.45065, 0.90124), control2: p(0.45103, 0.90206))
        path.addCurve(to: p(0.45408, 0.90754), control1: p(0.45205, 0.90332), control2: p(0.45319, 0.90546))
        path.addCurve(to: p(0.45833, 0.91598), control1: p(0.45503, 0.90954), control2: p(0.45694, 0.91338))
        path.addCurve(to: p(0.46081, 0.92094), control1: p(0.45967, 0.91849), control2: p(0.46081, 0.92079))
        path.addCurve(to: p(0.46303, 0.92523), control1: p(0.46081, 0.92108), control2: p(0.46183, 0.92301))
        path.addCurve(to: p(0.46526, 0.92967), control1: p(0.46424, 0.92745), control2: p(0.46526, 0.92945))
        path.addCurve(to: p(0.46748, 0.93411), control1: p(0.46526, 0.92989), control2: p(0.46627, 0.93189))
        path.addCurve(to: p(0.46970, 0.93863), control1: p(0.46869, 0.93633), control2: p(0.46970, 0.93841))
        path.addCurve(to: p(0.47193, 0.94314), control1: p(0.46970, 0.93885), control2: p(0.47072, 0.94092))
        path.addCurve(to: p(0.47415, 0.94751), control1: p(0.47313, 0.94537), control2: p(0.47415, 0.94729))
        path.addCurve(to: p(0.48253, 0.96395), control1: p(0.47415, 0.94781), control2: p(0.47745, 0.95432))
        path.addCurve(to: p(0.48495, 0.96898), control1: p(0.48387, 0.96646), control2: p(0.48495, 0.96876))
        path.addCurve(to: p(0.48742, 0.97402), control1: p(0.48495, 0.96920), control2: p(0.48603, 0.97150))
        path.addCurve(to: p(0.49435, 0.98749), control1: p(0.48876, 0.97653), control2: p(0.49187, 0.98260))
        path.addCurve(to: p(0.50292, 0.99933), control1: p(0.49917, 0.99711), control2: p(0.50019, 0.99859))
        path.addCurve(to: p(0.50769, 0.99541), control1: p(0.50502, 1.00000), control2: p(0.50603, 0.99911))
        path.addCurve(to: p(0.51315, 0.98423), control1: p(0.50953, 0.99134), control2: p(0.51137, 0.98756))
        path.addCurve(to: p(0.51480, 0.98075), control1: p(0.51410, 0.98260), control2: p(0.51480, 0.98105))
        path.addCurve(to: p(0.51601, 0.97838), control1: p(0.51480, 0.98053), control2: p(0.51531, 0.97942))
        path.addCurve(to: p(0.51956, 0.97120), control1: p(0.51664, 0.97727), control2: p(0.51823, 0.97402))
        path.addCurve(to: p(0.52268, 0.96491), control1: p(0.52090, 0.96832), control2: p(0.52229, 0.96550))
        path.addCurve(to: p(0.52528, 0.95973), control1: p(0.52312, 0.96432), control2: p(0.52426, 0.96195))
        path.addCurve(to: p(0.52814, 0.95381), control1: p(0.52623, 0.95751), control2: p(0.52757, 0.95484))
        path.addCurve(to: p(0.53163, 0.94677), control1: p(0.52877, 0.95277), control2: p(0.53030, 0.94959))
        path.addCurve(to: p(0.53474, 0.94048), control1: p(0.53296, 0.94389), control2: p(0.53436, 0.94107))
        path.addCurve(to: p(0.53697, 0.93604), control1: p(0.53519, 0.93989), control2: p(0.53614, 0.93789))
        path.addCurve(to: p(0.53919, 0.93160), control1: p(0.53779, 0.93419), control2: p(0.53881, 0.93219))
        path.addCurve(to: p(0.54179, 0.92641), control1: p(0.53963, 0.93100), control2: p(0.54078, 0.92863))
        path.addCurve(to: p(0.54465, 0.92049), control1: p(0.54275, 0.92419), control2: p(0.54408, 0.92153))
        path.addCurve(to: p(0.54815, 0.91346), control1: p(0.54529, 0.91946), control2: p(0.54681, 0.91627))
        path.addCurve(to: p(0.55138, 0.90709), control1: p(0.54948, 0.91057), control2: p(0.55094, 0.90776))
        path.addCurve(to: p(0.55227, 0.90546), control1: p(0.55189, 0.90650), control2: p(0.55227, 0.90576))
        path.addCurve(to: p(0.55513, 0.89932), control1: p(0.55227, 0.90517), control2: p(0.55354, 0.90243))
        path.addCurve(to: p(0.55799, 0.89340), control1: p(0.55672, 0.89628), control2: p(0.55799, 0.89354))
        path.addCurve(to: p(0.55964, 0.89007), control1: p(0.55799, 0.89325), control2: p(0.55869, 0.89169))
        path.addCurve(to: p(0.56250, 0.88451), control1: p(0.56053, 0.88844), control2: p(0.56180, 0.88592))
        path.addCurve(to: p(0.56860, 0.87215), control1: p(0.56320, 0.88303), control2: p(0.56593, 0.87748))
        path.addCurve(to: p(0.57470, 0.85979), control1: p(0.57127, 0.86675), control2: p(0.57400, 0.86119))
        path.addCurve(to: p(0.58943, 0.83017), control1: p(0.57768, 0.85349), control2: p(0.58816, 0.83254))
        path.addCurve(to: p(0.59883, 0.81093), control1: p(0.59102, 0.82714), control2: p(0.59610, 0.81678))
        path.addCurve(to: p(0.60144, 0.80574), control1: p(0.59985, 0.80871), control2: p(0.60105, 0.80634))
        path.addCurve(to: p(0.60366, 0.80130), control1: p(0.60182, 0.80515), control2: p(0.60283, 0.80315))
        path.addCurve(to: p(0.60588, 0.79686), control1: p(0.60448, 0.79945), control2: p(0.60550, 0.79745))
        path.addCurve(to: p(0.60849, 0.79168), control1: p(0.60633, 0.79627), control2: p(0.60747, 0.79390))
        path.addCurve(to: p(0.61134, 0.78576), control1: p(0.60944, 0.78946), control2: p(0.61077, 0.78679))
        path.addCurve(to: p(0.61484, 0.77872), control1: p(0.61198, 0.78472), control2: p(0.61350, 0.78154))
        path.addCurve(to: p(0.61795, 0.77243), control1: p(0.61617, 0.77584), control2: p(0.61757, 0.77302))
        path.addCurve(to: p(0.62017, 0.76799), control1: p(0.61839, 0.77184), control2: p(0.61935, 0.76984))
        path.addCurve(to: p(0.62754, 0.75318), control1: p(0.62176, 0.76444), control2: p(0.62525, 0.75748))
        path.addCurve(to: p(0.63135, 0.74541), control1: p(0.62830, 0.75178), control2: p(0.63002, 0.74822))
        path.addCurve(to: p(0.63446, 0.73912), control1: p(0.63269, 0.74252), control2: p(0.63408, 0.73971))
        path.addCurve(to: p(0.63707, 0.73394), control1: p(0.63491, 0.73853), control2: p(0.63605, 0.73616))
        path.addCurve(to: p(0.63993, 0.72801), control1: p(0.63802, 0.73171), control2: p(0.63935, 0.72905))
        path.addCurve(to: p(0.64367, 0.72061), control1: p(0.64050, 0.72698), control2: p(0.64221, 0.72365))
        path.addCurve(to: p(0.64691, 0.71395), control1: p(0.64513, 0.71757), control2: p(0.64660, 0.71454))
        path.addCurve(to: p(0.64983, 0.70802), control1: p(0.64729, 0.71336), control2: p(0.64856, 0.71069))
        path.addCurve(to: p(0.65377, 0.69988), control1: p(0.65111, 0.70536), control2: p(0.65288, 0.70173))
        path.addCurve(to: p(0.65650, 0.69455), control1: p(0.65466, 0.69803), control2: p(0.65587, 0.69566))
        path.addCurve(to: p(0.65771, 0.69226), control1: p(0.65720, 0.69351), control2: p(0.65771, 0.69248))
        path.addCurve(to: p(0.66152, 0.68434), control1: p(0.65771, 0.69203), control2: p(0.65943, 0.68848))
        path.addCurve(to: p(0.66533, 0.67649), control1: p(0.66362, 0.68019), control2: p(0.66533, 0.67664))
        path.addCurve(to: p(0.66756, 0.67205), control1: p(0.66533, 0.67627), control2: p(0.66635, 0.67427))
        path.addCurve(to: p(0.66978, 0.66775), control1: p(0.66876, 0.66983), control2: p(0.66978, 0.66790))
        path.addCurve(to: p(0.67581, 0.65546), control1: p(0.66978, 0.66760), control2: p(0.67251, 0.66205))
        path.addCurve(to: p(0.68185, 0.64317), control1: p(0.67912, 0.64887), control2: p(0.68185, 0.64332))
        path.addCurve(to: p(0.68350, 0.63984), control1: p(0.68185, 0.64295), control2: p(0.68255, 0.64147))
        path.addCurve(to: p(0.68636, 0.63429), control1: p(0.68439, 0.63821), control2: p(0.68566, 0.63570))
        path.addCurve(to: p(0.69245, 0.62193), control1: p(0.68706, 0.63281), control2: p(0.68979, 0.62726))
        path.addCurve(to: p(0.69919, 0.60808), control1: p(0.69512, 0.61652), control2: p(0.69817, 0.61031))
        path.addCurve(to: p(0.70166, 0.60379), control1: p(0.70027, 0.60586), control2: p(0.70135, 0.60386))
        path.addCurve(to: p(0.70217, 0.60283), control1: p(0.70192, 0.60364), control2: p(0.70217, 0.60320))
        path.addCurve(to: p(0.70776, 0.59098), control1: p(0.70217, 0.60246), control2: p(0.70465, 0.59713))
        path.addCurve(to: p(0.71481, 0.57677), control1: p(0.71081, 0.58491), control2: p(0.71399, 0.57847))
        path.addCurve(to: p(0.72313, 0.55996), control1: p(0.71684, 0.57255), control2: p(0.72110, 0.56404))
        path.addCurve(to: p(0.72720, 0.55182), control1: p(0.72409, 0.55811), control2: p(0.72593, 0.55449))
        path.addCurve(to: p(0.73012, 0.54590), control1: p(0.72847, 0.54916), control2: p(0.72980, 0.54649))
        path.addCurve(to: p(0.73304, 0.53998), control1: p(0.73050, 0.54531), control2: p(0.73177, 0.54264))
        path.addCurve(to: p(0.73863, 0.52865), control1: p(0.73438, 0.53731), control2: p(0.73685, 0.53220))
        path.addCurve(to: p(0.74339, 0.51903), control1: p(0.74041, 0.52502), control2: p(0.74257, 0.52065))
        path.addCurve(to: p(0.74587, 0.51407), control1: p(0.74422, 0.51732), control2: p(0.74530, 0.51510))
        path.addCurve(to: p(0.74873, 0.50822), control1: p(0.74644, 0.51303), control2: p(0.74771, 0.51044))
        path.addCurve(to: p(0.75178, 0.50215), control1: p(0.74975, 0.50600), control2: p(0.75108, 0.50326))
        path.addCurve(to: p(0.75299, 0.49978), control1: p(0.75241, 0.50104), control2: p(0.75299, 0.50000))
        path.addCurve(to: p(0.75680, 0.49186), control1: p(0.75299, 0.49956), control2: p(0.75470, 0.49600))
        path.addCurve(to: p(0.76061, 0.48401), control1: p(0.75889, 0.48771), control2: p(0.76061, 0.48416))
        path.addCurve(to: p(0.76283, 0.47957), control1: p(0.76061, 0.48379), control2: p(0.76162, 0.48179))
        path.addCurve(to: p(0.76505, 0.47527), control1: p(0.76404, 0.47735), control2: p(0.76505, 0.47542))
        path.addCurve(to: p(0.76886, 0.46743), control1: p(0.76505, 0.47505), control2: p(0.76677, 0.47157))
        path.addCurve(to: p(0.77268, 0.45951), control1: p(0.77096, 0.46328), control2: p(0.77268, 0.45973))
        path.addCurve(to: p(0.77388, 0.45721), control1: p(0.77268, 0.45928), control2: p(0.77318, 0.45825))
        path.addCurve(to: p(0.77744, 0.45003), control1: p(0.77452, 0.45610), control2: p(0.77611, 0.45284))
        path.addCurve(to: p(0.78068, 0.44366), control1: p(0.77877, 0.44714), control2: p(0.78023, 0.44433))
        path.addCurve(to: p(0.78157, 0.44203), control1: p(0.78119, 0.44307), control2: p(0.78157, 0.44226))
        path.addCurve(to: p(0.78538, 0.43404), control1: p(0.78157, 0.44174), control2: p(0.78328, 0.43818))
        path.addCurve(to: p(0.78919, 0.42619), control1: p(0.78747, 0.42997), control2: p(0.78919, 0.42641))
        path.addCurve(to: p(0.79040, 0.42390), control1: p(0.78919, 0.42597), control2: p(0.78970, 0.42493))
        path.addCurve(to: p(0.79395, 0.41672), control1: p(0.79103, 0.42279), control2: p(0.79262, 0.41953))
        path.addCurve(to: p(0.79719, 0.41035), control1: p(0.79529, 0.41383), control2: p(0.79675, 0.41102))
        path.addCurve(to: p(0.79808, 0.40872), control1: p(0.79770, 0.40976), control2: p(0.79808, 0.40902))
        path.addCurve(to: p(0.80094, 0.40258), control1: p(0.79808, 0.40842), control2: p(0.79935, 0.40569))
        path.addCurve(to: p(0.80380, 0.39673), control1: p(0.80253, 0.39954), control2: p(0.80380, 0.39688))
        path.addCurve(to: p(0.80659, 0.39095), control1: p(0.80380, 0.39658), control2: p(0.80507, 0.39399))
        path.addCurve(to: p(0.82069, 0.36253), control1: p(0.80983, 0.38459), control2: p(0.81847, 0.36719))
        path.addCurve(to: p(0.82647, 0.35105), control1: p(0.82152, 0.36082), control2: p(0.82412, 0.35564))
        path.addCurve(to: p(0.83822, 0.32751), control1: p(0.83181, 0.34046), control2: p(0.83435, 0.33536))
        path.addCurve(to: p(0.84191, 0.32011), control1: p(0.83994, 0.32403), control2: p(0.84159, 0.32070))
        path.addCurve(to: p(0.84909, 0.30530), control1: p(0.84261, 0.31885), control2: p(0.84616, 0.31152))
        path.addCurve(to: p(0.85340, 0.29664), control1: p(0.85010, 0.30308), control2: p(0.85207, 0.29916))
        path.addCurve(to: p(0.85588, 0.29153), control1: p(0.85480, 0.29412), control2: p(0.85588, 0.29183))
        path.addCurve(to: p(0.85728, 0.28879), control1: p(0.85588, 0.29131), control2: p(0.85652, 0.29005))
        path.addCurve(to: p(0.86084, 0.28161), control1: p(0.85804, 0.28753), control2: p(0.85969, 0.28428))
        path.addCurve(to: p(0.86376, 0.27569), control1: p(0.86204, 0.27895), control2: p(0.86331, 0.27628))
        path.addCurve(to: p(0.86636, 0.27051), control1: p(0.86420, 0.27510), control2: p(0.86535, 0.27273))
        path.addCurve(to: p(0.86922, 0.26458), control1: p(0.86731, 0.26829), control2: p(0.86865, 0.26562))
        path.addCurve(to: p(0.87271, 0.25755), control1: p(0.86986, 0.26355), control2: p(0.87138, 0.26036))
        path.addCurve(to: p(0.87583, 0.25126), control1: p(0.87405, 0.25466), control2: p(0.87544, 0.25185))
        path.addCurve(to: p(0.87805, 0.24682), control1: p(0.87627, 0.25067), control2: p(0.87722, 0.24867))
        path.addCurve(to: p(0.88027, 0.24237), control1: p(0.87887, 0.24497), control2: p(0.87989, 0.24297))
        path.addCurve(to: p(0.88288, 0.23719), control1: p(0.88072, 0.24178), control2: p(0.88186, 0.23941))
        path.addCurve(to: p(0.88573, 0.23127), control1: p(0.88383, 0.23497), control2: p(0.88516, 0.23231))
        path.addCurve(to: p(0.88923, 0.22424), control1: p(0.88637, 0.23023), control2: p(0.88789, 0.22705))
        path.addCurve(to: p(0.89247, 0.21787), control1: p(0.89056, 0.22135), control2: p(0.89202, 0.21854))
        path.addCurve(to: p(0.89336, 0.21632), control1: p(0.89298, 0.21728), control2: p(0.89336, 0.21654))
        path.addCurve(to: p(0.90009, 0.20218), control1: p(0.89336, 0.21587), control2: p(0.89475, 0.21291))
        path.addCurve(to: p(0.90358, 0.19514), control1: p(0.90136, 0.19966), control2: p(0.90295, 0.19648))
        path.addCurve(to: p(0.90968, 0.18293), control1: p(0.90428, 0.19381), control2: p(0.90701, 0.18826))
        path.addCurve(to: p(0.91610, 0.16990), control1: p(0.91235, 0.17752), control2: p(0.91521, 0.17168))
        path.addCurve(to: p(0.92264, 0.15672), control1: p(0.91692, 0.16812), control2: p(0.91991, 0.16220))
        path.addCurve(to: p(0.92765, 0.14643), control1: p(0.92537, 0.15117), control2: p(0.92765, 0.14658))
        path.addCurve(to: p(0.92931, 0.14310), control1: p(0.92765, 0.14621), control2: p(0.92835, 0.14473))
        path.addCurve(to: p(0.93204, 0.13777), control1: p(0.93020, 0.14147), control2: p(0.93140, 0.13903))
        path.addCurve(to: p(0.93788, 0.12600), control1: p(0.93267, 0.13644), control2: p(0.93528, 0.13118))
        path.addCurve(to: p(0.94366, 0.11423), control1: p(0.94049, 0.12082), control2: p(0.94309, 0.11549))
        path.addCurve(to: p(0.95211, 0.09728), control1: p(0.94519, 0.11090), control2: p(0.95039, 0.10038))
        path.addCurve(to: p(0.95592, 0.08950), control1: p(0.95287, 0.09587), control2: p(0.95459, 0.09232))
        path.addCurve(to: p(0.95903, 0.08321), control1: p(0.95725, 0.08662), control2: p(0.95865, 0.08380))
        path.addCurve(to: p(0.96164, 0.07803), control1: p(0.95948, 0.08262), control2: p(0.96062, 0.08025))
        path.addCurve(to: p(0.96449, 0.07211), control1: p(0.96259, 0.07581), control2: p(0.96392, 0.07314))
        path.addCurve(to: p(0.96837, 0.06448), control1: p(0.96507, 0.07107), control2: p(0.96684, 0.06766))
        path.addCurve(to: p(0.97561, 0.04982), control1: p(0.97345, 0.05382), control2: p(0.97497, 0.05086))
        path.addCurve(to: p(0.97815, 0.04471), control1: p(0.97599, 0.04923), control2: p(0.97713, 0.04694))
        path.addCurve(to: p(0.98101, 0.03879), control1: p(0.97910, 0.04249), control2: p(0.98044, 0.03983))
        path.addCurve(to: p(0.98450, 0.03176), control1: p(0.98164, 0.03776), control2: p(0.98317, 0.03457))
        path.addCurve(to: p(0.98761, 0.02547), control1: p(0.98584, 0.02887), control2: p(0.98723, 0.02606))
        path.addCurve(to: p(0.98952, 0.02176), control1: p(0.98800, 0.02487), control2: p(0.98888, 0.02317))
        path.addCurve(to: p(0.99428, 0.01303), control1: p(0.99022, 0.02036), control2: p(0.99231, 0.01643))
        path.addCurve(to: p(0.99962, 0.00207), control1: p(0.99987, 0.00333), control2: p(1.00000, 0.00311))
        path.addCurve(to: p(0.81625, 0.00104), control1: p(0.99936, 0.00118), control2: p(0.97040, 0.00104))
        path.addCurve(to: p(0.63129, 0.00244), control1: p(0.63827, 0.00104), control2: p(0.63319, 0.00111))
        path.closeSubpath()
        return path
    }
}
