import Cocoa
import CoreGraphics

func renderAppIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    ctx.clear(rect)
    
    // 1. Apple 官方规范 Squircle 连续曲率圆角底座 (896x896，居中边距 64px, 圆角 200px)
    let squircleRect = CGRect(x: 64, y: 64, width: 896, height: 896)
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: 200, cornerHeight: 200, transform: nil)
    
    // 底座深邃深空钛金渐变 (#181b22 -> #0b0c10)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray
    let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0])!
    
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: 960), end: CGPoint(x: 512, y: 64), options: [])
    
    // 底座中心放射性环境微光 (Cyan & Violet Glow)
    let glowColors = [
        NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.28).cgColor,
        NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 0.15).cgColor,
        NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0).cgColor
    ] as CFArray
    let centerGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 0.45, 1.0])!
    ctx.drawRadialGradient(centerGrad, startCenter: CGPoint(x: 512, y: 512), startRadius: 0, endCenter: CGPoint(x: 512, y: 512), endRadius: 450, options: [])
    ctx.restoreGState()
    
    // 1px 细致玻璃倒角边框高光
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
    ctx.strokePath()
    ctx.restoreGState()
    
    // 2. 绘制核心高颜值极简几何折叠 "Z" 符号 (Bold Precision Z)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.65).cgColor)
    
    // (A) 顶横梁：电光青蓝渐变 (#38bdf8 -> #0284c7)
    let topPath = CGMutablePath()
    topPath.move(to: CGPoint(x: 270, y: 720))
    topPath.addLine(to: CGPoint(x: 754, y: 720))
    topPath.addLine(to: CGPoint(x: 754, y: 624))
    topPath.addLine(to: CGPoint(x: 410, y: 624))
    topPath.addLine(to: CGPoint(x: 270, y: 720))
    topPath.closeSubpath()
    
    let topColors = [
        NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor,
        NSColor(red: 0.01, green: 0.52, blue: 0.78, alpha: 1.0).cgColor
    ] as CFArray
    let topGrad = CGGradient(colorsSpace: colorSpace, colors: topColors, locations: [0.0, 1.0])!
    
    ctx.saveGState()
    ctx.addPath(topPath)
    ctx.clip()
    ctx.drawLinearGradient(topGrad, start: CGPoint(x: 270, y: 672), end: CGPoint(x: 754, y: 672), options: [])
    ctx.restoreGState()
    
    // (B) 底部基座：极光紫至深洋红渐变 (#9333ea -> #c026d3)
    let botPath = CGMutablePath()
    botPath.move(to: CGPoint(x: 270, y: 304))
    botPath.addLine(to: CGPoint(x: 754, y: 304))
    botPath.addLine(to: CGPoint(x: 754, y: 400))
    botPath.addLine(to: CGPoint(x: 614, y: 400))
    botPath.addLine(to: CGPoint(x: 270, y: 304))
    botPath.closeSubpath()
    
    let botColors = [
        NSColor(red: 0.58, green: 0.20, blue: 0.92, alpha: 1.0).cgColor,
        NSColor(red: 0.75, green: 0.15, blue: 0.83, alpha: 1.0).cgColor
    ] as CFArray
    let botGrad = CGGradient(colorsSpace: colorSpace, colors: botColors, locations: [0.0, 1.0])!
    
    ctx.saveGState()
    ctx.addPath(botPath)
    ctx.clip()
    ctx.drawLinearGradient(botGrad, start: CGPoint(x: 270, y: 352), end: CGPoint(x: 754, y: 352), options: [])
    ctx.restoreGState()
    
    // (C) 对角折梁：充满能量流动感的电光靛紫渐变 (#38bdf8 -> #6366f1 -> #a855f7)
    let diagPath = CGMutablePath()
    diagPath.move(to: CGPoint(x: 754, y: 720))
    diagPath.addLine(to: CGPoint(x: 754, y: 624))
    diagPath.addLine(to: CGPoint(x: 410, y: 400))
    diagPath.addLine(to: CGPoint(x: 270, y: 304))
    diagPath.addLine(to: CGPoint(x: 270, y: 400))
    diagPath.addLine(to: CGPoint(x: 614, y: 624))
    diagPath.closeSubpath()
    
    let diagColors = [
        NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1.0).cgColor,
        NSColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 1.0).cgColor,
        NSColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1.0).cgColor
    ] as CFArray
    let diagGrad = CGGradient(colorsSpace: colorSpace, colors: diagColors, locations: [0.0, 0.5, 1.0])!
    
    ctx.saveGState()
    ctx.addPath(diagPath)
    ctx.clip()
    ctx.drawLinearGradient(diagGrad, start: CGPoint(x: 754, y: 720), end: CGPoint(x: 270, y: 304), options: [])
    ctx.restoreGState()
    
    ctx.restoreGState()
    
    // 3. 右上方代码星芒能量核 (Prompt Magic Core)
    ctx.saveGState()
    let sparkCenter = CGPoint(x: 754, y: 725)
    let sparkPath = CGMutablePath()
    sparkPath.move(to: CGPoint(x: sparkCenter.x, y: sparkCenter.y + 24))
    sparkPath.addLine(to: CGPoint(x: sparkCenter.x + 18, y: sparkCenter.y))
    sparkPath.addLine(to: CGPoint(x: sparkCenter.x, y: sparkCenter.y - 24))
    sparkPath.addLine(to: CGPoint(x: sparkCenter.x - 18, y: sparkCenter.y))
    sparkPath.closeSubpath()
    
    ctx.setFillColor(NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.95).cgColor)
    ctx.addPath(sparkPath)
    ctx.fillPath()
    
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: sparkCenter.x - 5, y: sparkCenter.y - 5, width: 10, height: 10))
    ctx.restoreGState()
    
    image.unlockFocus()
    return image
}

let icon = renderAppIcon()
guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert icon to PNG")
}

let outputPath = "/Users/lifengju/【01】我的开发/prompt-enhancer/assets/app-icon.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("✅ CoreGraphics 成功渲染 1024x1024 高清无损应用图标！")
