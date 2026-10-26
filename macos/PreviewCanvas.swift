import AppKit
import SwiftUI

struct CanvasCommand: Equatable {
    enum Action { case fit, actual, zoomIn, zoomOut }
    var action: Action = .fit
    var id = UUID()
}
private final class CenteredClip: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        if let doc = documentView {
            if doc.frame.width < rect.width { rect.origin.x = (doc.frame.width-rect.width)/2 }
            if doc.frame.height < rect.height { rect.origin.y = (doc.frame.height-rect.height)/2 }
        }
        return rect
    }
}
final class PaperDocument: NSView {
    var pictures: [NSImage] = []
    var rectangles: [NSRect] = []
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .high
        for (image, rect) in zip(pictures, rectangles) where rect.intersects(dirtyRect) {
            NSColor.white.setFill(); NSBezierPath(rect: rect).fill()
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { enclosingScrollView?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { enclosingScrollView?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { enclosingScrollView?.mouseUp(with: event) }
    override func keyDown(with event: NSEvent) { enclosingScrollView?.keyDown(with: event) }
}
final class PaperScroll: NSScrollView {
    let paper = PaperDocument()
    var fitMode = true
    private var lastSize = NSSize.zero
    private var scale: CGFloat = 1
    private var dragStart: NSPoint?
    private var origin = NSPoint.zero
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = CenteredClip(); documentView = paper
        hasHorizontalScroller = true; hasVerticalScroller = true
        autohidesScrollers = true; borderType = .noBorder
        drawsBackground = true; backgroundColor = .underPageBackgroundColor
        allowsMagnification = true; minMagnification = 0.02; maxMagnification = 16
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); arrange(); if fitMode { fit() } }
    func setPictures(_ pictures: [NSImage]) {
        guard pictures.count != paper.pictures.count || zip(pictures, paper.pictures).contains(where: { pair in pair.0 !== pair.1 }) else { return }
        let old = paper.frame.size
        let midpoint = NSPoint(x: contentView.bounds.midX/max(1,old.width), y: contentView.bounds.midY/max(1,old.height))
        paper.pictures = pictures; arrange()
        if fitMode { fit() }
        else { setMagnification(magnification, centeredAt: NSPoint(x: midpoint.x*paper.frame.width, y: midpoint.y*paper.frame.height)) }
    }
    private func arrange() {
        scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let sizes = paper.pictures.map { image -> NSSize in
            let rep = image.representations.first
            return NSSize(width: CGFloat(rep?.pixelsWide ?? Int(image.size.width))/scale,
                          height: CGFloat(rep?.pixelsHigh ?? Int(image.size.height))/scale)
        }
        let maxHeight = sizes.map(\.height).max() ?? 1
        var x: CGFloat = 36; paper.rectangles = []
        for size in sizes { paper.rectangles.append(NSRect(x: x, y: 36+(maxHeight-size.height)/2, width: size.width, height: size.height)); x += size.width+24 }
        paper.frame = NSRect(x: 0, y: 0, width: max(1,x+12), height: max(1,maxHeight+72))
        paper.needsDisplay = true
    }
    override func layout() {
        super.layout()
        if bounds.size != lastSize { lastSize = bounds.size; if fitMode { fit() } }
    }
    func fit() {
        fitMode = true
        let size = contentView.frame.size, document = paper.frame.size
        guard size.width > 0, size.height > 0, document.width > 0, document.height > 0 else { return }
        let value = min(size.width/document.width, size.height/document.height)
        setMagnification(max(minMagnification,min(maxMagnification,value)), centeredAt: NSPoint(x: document.width/2,y:document.height/2))
    }
    func command(_ action: CanvasCommand.Action) {
        switch action {
        case .fit: fit()
        case .actual: fitMode = false; setMagnification(1, centeredAt: NSPoint(x: contentView.bounds.midX,y:contentView.bounds.midY))
        case .zoomIn: zoom(1.25)
        case .zoomOut: zoom(0.8)
        }
    }
    private func zoom(_ factor: CGFloat, point: NSPoint? = nil) {
        fitMode = false
        setMagnification(max(minMagnification,min(maxMagnification,magnification*factor)), centeredAt: point ?? NSPoint(x:contentView.bounds.midX,y:contentView.bounds.midY))
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            let point = paper.convert(event.locationInWindow, from: nil)
            if abs(magnification-1) < 0.01 { fit() } else { fitMode = false; setMagnification(1, centeredAt: point) }
            return
        }
        dragStart = event.locationInWindow; origin = contentView.bounds.origin; NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = event.locationInWindow
        let point = NSPoint(x: origin.x-(now.x-start.x)/magnification, y: origin.y+(now.y-start.y)/magnification)
        contentView.scroll(to: point); reflectScrolledClipView(contentView)
    }
    override func mouseUp(with event: NSEvent) { if dragStart != nil { NSCursor.pop() }; dragStart = nil }
    override func magnify(with event: NSEvent) { fitMode = false; super.magnify(with: event) }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            zoom(exp(event.scrollingDeltaY*0.025), point: paper.convert(event.locationInWindow, from: nil))
        } else { super.scrollWheel(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "+", "=": command(.zoomIn)
        case "-": command(.zoomOut)
        case "0": command(.fit)
        case "1": command(.actual)
        default: super.keyDown(with: event)
        }
    }
}
struct PreviewCanvas: NSViewRepresentable {
    var images: [NSImage]
    var command: CanvasCommand
    @Binding var zoom: Double
    final class Coordinator {
        var parent: PreviewCanvas
        var observed: NSKeyValueObservation?
        var lastCommand: UUID?
        init(_ parent: PreviewCanvas) { self.parent = parent }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = PaperScroll(frame: .zero)
        context.coordinator.observed = scroll.observe(\.magnification, options: [.new]) { [weak coordinator = context.coordinator] view, _ in
            let value = Double(view.magnification)
            DispatchQueue.main.async { if let c = coordinator, abs(c.parent.zoom-value) > 0.0001 { c.parent.zoom = value } }
        }
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let scroll = view as? PaperScroll else { return }
        context.coordinator.parent = self; scroll.setPictures(images)
        if context.coordinator.lastCommand != command.id { context.coordinator.lastCommand = command.id; scroll.command(command.action) }
    }
}
struct PreviewPanel: View {
    @EnvironmentObject var model: Model
    @State private var command = CanvasCommand()
    @State private var zoom = 1.0
    private var images: [NSImage] {
        let first = model.showOriginal ? model.original : model.enhanced
        let second = model.showOriginal ? model.secondOriginal : model.secondEnhanced
        let values = [first, model.doublePreview ? second : nil].compactMap { $0 }
        return model.rightToLeft ? Array(values.reversed()) : values
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("适应") { command = CanvasCommand(action: .fit) }
                Button("100%") { command = CanvasCommand(action: .actual) }.help("一个图像像素对应一个屏幕像素；精查请开启全尺寸。")
                Button { command = CanvasCommand(action: .zoomOut) } label: { Image(systemName: "minus.magnifyingglass") }
                Text(zoom, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).frame(width: 48)
                Button { command = CanvasCommand(action: .zoomIn) } label: { Image(systemName: "plus.magnifyingglass") }
                Spacer()
                Menu {
                    Toggle("双页同时预览", isOn: $model.doublePreview)
                    Toggle("右开书（左右交换）", isOn: $model.rightToLeft)
                    Toggle("全尺寸细节预览", isOn: $model.fullPreview)
                    Toggle("显示原图", isOn: $model.showOriginal)
                } label: { Label("预览", systemImage: "rectangle.split.2x1") }
            }.controlSize(.small).padding(12)
            ZStack {
                PreviewCanvas(images: images, command: command, zoom: $zoom)
                if images.isEmpty && !model.previewing {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed.fill").font(.system(size: 52)).foregroundStyle(.teal)
                        Text("每一页，都有自己的处理流程").font(.title3.weight(.medium))
                        Button("导入图片 / PDF", action: model.addFiles).buttonStyle(.borderedProminent)
                    }
                }
                if model.previewing { ProgressView().padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            HStack {
                Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }.disabled((model.activeIndex ?? 0) == 0)
                Text(model.activeIndex.map { String(format:"%04d",$0) } ?? "—").font(.caption.monospacedDigit())
                Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }.disabled((model.activeIndex ?? 0)+1 >= model.files.count)
                Spacer()
                Text("拖动平移 · 捏合缩放 · ⌘滚轮 · 双击 100% / 适应").font(.caption2).foregroundStyle(.secondary)
            }.controlSize(.small).padding(12)
        }
        .onChange(of: model.selection) { _ in command = CanvasCommand(action: .fit) }
    }
}
