import AppKit

let outputURL = URL(fileURLWithPath: "Sources/RumbaMacApp/Resources/Branding/rumba-logo-1024.png")
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let background = NSColor(calibratedWhite: 0.92, alpha: 1.0)
background.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

let strokeColor = NSColor.black
strokeColor.setStroke()

let top = NSBezierPath()
top.lineWidth = 34
top.lineCapStyle = .round
top.lineJoinStyle = .round
top.move(to: NSPoint(x: 190, y: 565))
top.curve(to: NSPoint(x: 380, y: 735), controlPoint1: NSPoint(x: 120, y: 625), controlPoint2: NSPoint(x: 245, y: 765))
top.curve(to: NSPoint(x: 500, y: 765), controlPoint1: NSPoint(x: 410, y: 730), controlPoint2: NSPoint(x: 455, y: 770))
top.curve(to: NSPoint(x: 645, y: 735), controlPoint1: NSPoint(x: 555, y: 770), controlPoint2: NSPoint(x: 615, y: 750))
top.curve(to: NSPoint(x: 835, y: 565), controlPoint1: NSPoint(x: 770, y: 765), controlPoint2: NSPoint(x: 905, y: 625))
top.curve(to: NSPoint(x: 770, y: 485), controlPoint1: NSPoint(x: 840, y: 515), controlPoint2: NSPoint(x: 800, y: 485))
top.curve(to: NSPoint(x: 695, y: 525), controlPoint1: NSPoint(x: 745, y: 485), controlPoint2: NSPoint(x: 720, y: 505))
top.stroke()

let left = NSBezierPath()
left.lineWidth = 34
left.lineCapStyle = .round
left.lineJoinStyle = .round
left.move(to: NSPoint(x: 330, y: 615))
left.curve(to: NSPoint(x: 285, y: 300), controlPoint1: NSPoint(x: 275, y: 450), controlPoint2: NSPoint(x: 250, y: 360))
left.curve(to: NSPoint(x: 385, y: 250), controlPoint1: NSPoint(x: 290, y: 270), controlPoint2: NSPoint(x: 335, y: 260))
left.stroke()

let right = NSBezierPath()
right.lineWidth = 34
right.lineCapStyle = .round
right.lineJoinStyle = .round
right.move(to: NSPoint(x: 695, y: 615))
right.curve(to: NSPoint(x: 740, y: 300), controlPoint1: NSPoint(x: 750, y: 450), controlPoint2: NSPoint(x: 775, y: 360))
right.curve(to: NSPoint(x: 640, y: 250), controlPoint1: NSPoint(x: 735, y: 270), controlPoint2: NSPoint(x: 690, y: 260))
right.stroke()

image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let pngData = rep.representation(using: .png, properties: [:])!

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try pngData.write(to: outputURL)
print("Wrote \(outputURL.path)")
