import AppKit

enum DemoFrame {
    /// Deliberately fictional content; does not read any files or accounts.
    static func make() -> CGImage? {
        let size = NSSize(width: 1440, height: 900)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            color.setFill(); NSBezierPath(rect: NSRect(x: x, y: 900-y-h, width: w, height: h)).fill()
        }
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat = 20, _ color: NSColor = .labelColor, _ weight: NSFont.Weight = .regular) {
            (value as NSString).draw(at: NSPoint(x: x, y: 900-y-size-7), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        let ink = NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.22, alpha: 1)
        let muted = NSColor(calibratedRed: 0.43, green: 0.49, blue: 0.55, alpha: 1)
        box(0, 0, 1440, 60, NSColor(calibratedWhite: 0.89, alpha: 1))
        text("●  ●  ●", 24, 15, 17, muted)
        box(170, 11, 650, 37, .white)
        text("demo.example / project / overview", 194, 18, 15, muted)
        box(0, 60, 235, 840, .white)
        text("FIELDNOTES", 28, 100, 21, ink, .bold)
        for (index, title) in ["Overview", "Projects", "People", "Invoices", "Settings"].enumerated() {
            if index == 0 { box(16, 177, 203, 48, NSColor(calibratedRed: 0.9, green: 0.96, blue: 0.93, alpha: 1)) }
            text(title, 36, CGFloat(187+index*62), 18, ink, index == 0 ? .semibold : .regular)
        }
        text("DEMO WORKSPACE", 280, 101, 14, muted, .semibold)
        text("Project overview", 280, 137, 38, ink, .bold)
        text("A safe place to try your first privacy mask.", 280, 194, 21, muted)
        box(280, 263, 1105, 154, .white)
        text("This month's revenue", 310, 285, 17, muted)
        text("₹ 2,48,500", 310, 325, 38, ink, .semibold)
        text("Active projects", 740, 285, 17, muted)
        text("12", 740, 325, 38, ink, .semibold)
        text("TEAM DIRECTORY", 280, 466, 15, muted, .semibold)
        box(280, 508, 1105, 265, .white)
        text("Name", 310, 529, 16, muted, .semibold)
        text("Email · try covering this column", 625, 529, 16, muted, .semibold)
        text("Role", 1120, 529, 16, muted, .semibold)
        let rows = [("Aarav Shah", "aarav@example.test", "Designer"), ("Meera Rao", "meera@example.test", "Engineer"), ("Kabir Patel", "kabir@example.test", "Product")]
        for (i, row) in rows.enumerated() {
            let y = CGFloat(584+i*62)
            box(310, y-14, 1045, 1, NSColor(calibratedWhite: 0.93, alpha: 1))
            text(row.0, 310, y, 20, ink); text(row.1, 625, y, 20, ink); text(row.2, 1120, y, 18, muted)
        }
        text("Fictional data · nothing here comes from your computer", 280, 820, 16, muted)
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
