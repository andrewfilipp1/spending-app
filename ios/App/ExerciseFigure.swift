import SpendingCore
import SwiftUI

/// Draws the animated stick figure for an exercise, from the shared pose data in SpendingCore.
/// The motion eases and ping-pongs between the two key poses — the same engine as the web preview.
struct ExerciseFigure: View {
    let exercise: Exercise
    var playing = true
    var color: Color = .brand
    var lineWidth: Double = 0.05   // as a fraction of the box size

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !playing || reduceMotion)) { timeline in
            Canvas { ctx, size in
                draw(ctx, size: size, t: phase(timeline.date))
            }
        }
        .accessibilityHidden(true)
    }

    /// Triangle wave in 0…1 (ping-pong). When motion is reduced, hold the "working" pose.
    private func phase(_ date: Date) -> Double {
        guard playing, !reduceMotion else { return 1 }
        let p = (date.timeIntervalSinceReferenceDate / exercise.period).truncatingRemainder(dividingBy: 2)
        return p < 1 ? p : 2 - p
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let box = min(size.width, size.height)
        let pad = box * 0.05
        let s = box - pad * 2
        let ox = (size.width - s) / 2
        let oy = (size.height - s) / 2
        func pt(_ j: Joint) -> CGPoint { CGPoint(x: ox + j.x / 100 * s, y: oy + j.y / 100 * s) }

        let joints = exercise.interpolated(t)
        let groundY = oy + exercise.ground / 100 * s

        // wall (e.g. wall sit): a faint vertical surface behind the back
        if exercise.wall == true, let back = joints[exercise.head] {
            let wx = ox + (back.x - 6) / 100 * s
            var wall = Path()
            wall.move(to: CGPoint(x: wx, y: oy + 0.12 * s))
            wall.addLine(to: CGPoint(x: wx, y: groundY))
            ctx.stroke(wall, with: .color(color.opacity(0.28)), style: StrokeStyle(lineWidth: s * 0.02, lineCap: .round))
        }

        // ground shadow under the figure
        let cx = joints.values.map { ox + $0.x / 100 * s }.reduce(0, +) / Double(max(joints.count, 1))
        let shadow = Path(ellipseIn: CGRect(x: cx - s * 0.28, y: groundY, width: s * 0.56, height: s * 0.03))
        ctx.fill(shadow, with: .color(.black.opacity(0.12)))

        // bones
        let w = s * lineWidth
        for bone in exercise.bones where bone.count == 2 {
            guard let a = joints[bone[0]], let b = joints[bone[1]] else { continue }
            var p = Path()
            p.move(to: pt(a))
            p.addLine(to: pt(b))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }

        // head
        if let h = joints[exercise.head] {
            let r = exercise.hr / 100 * s
            let c = pt(h)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }
}
