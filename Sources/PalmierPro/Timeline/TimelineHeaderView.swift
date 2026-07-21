import AppKit

/// Fixed track header column drawn to the left of the scrollable timeline.
final class TimelineHeaderView: NSView {
    unowned var editor: EditorViewModel

    var requestCanvasRedraw: (() -> Void)?

    private static let headerBg = AppTheme.Background.surface.cgColor
    private static let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: AppTheme.FontSize.sm, weight: .medium),
        .foregroundColor: AppTheme.Text.secondary,
    ]

    /// Rects for mute/solo/hide/sync-lock buttons and the gain fader, indexed by track. Used for hit testing.
    var muteButtonRects: [Int: NSRect] = [:]
    var soloButtonRects: [Int: NSRect] = [:]
    var hideButtonRects: [Int: NSRect] = [:]
    var syncLockButtonRects: [Int: NSRect] = [:]
    var gainFaderRects: [Int: NSRect] = [:]
    var dragHandleRects: [Int: NSRect] = [:]

    /// Minimum track height at which the audio lane's gain fader is shown.
    private static let faderMinTrackHeight: CGFloat = 44

    init(editor: EditorViewModel) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Self.headerBg
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background
        ctx.setFillColor(Self.headerBg)
        ctx.fill(bounds)

        let rulerBottom = bounds.origin.y + Layout.rulerHeight - 0.5
        ctx.setFillColor(AppTheme.Border.primary.cgColor)
        ctx.fill(NSRect(x: 0, y: rulerBottom, width: bounds.width, height: 1))

        // Clip drawing below the ruler so headers don't overlap it when scrolled
        let clipTop = bounds.origin.y + Layout.rulerHeight
        ctx.clip(to: NSRect(x: bounds.origin.x, y: clipTop, width: bounds.width, height: bounds.height))

        muteButtonRects.removeAll()
        soloButtonRects.removeAll()
        hideButtonRects.removeAll()
        syncLockButtonRects.removeAll()
        gainFaderRects.removeAll()
        dragHandleRects.removeAll()
        let stripWidth: CGFloat = 3
        let iconSize: CGFloat = 14
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let headerWidth = bounds.width

        let geo = TimelineGeometry(editor: editor, bounds: bounds)

        for (i, track) in editor.timeline.tracks.enumerated() {
            let y = geo.trackY(at: i)
            let h = geo.trackHeight(at: i)

            // Lift the row being dragged
            if reorderDrag?.id == track.id {
                ctx.setFillColor(AppTheme.Background.prominent.cgColor)
                ctx.fill(NSRect(x: 0, y: y, width: headerWidth, height: h))
            }

            // Color-coded left border strip
            ctx.setFillColor(track.type.themeColor.cgColor)
            ctx.fill(NSRect(x: 0, y: y, width: stripWidth, height: h))

            let isAudio = track.type == .audio
            let showFader = isAudio && h >= Self.faderMinTrackHeight

            // With a fader on the lower line, the top row (grip, label, icons) is pinned near the top.
            let rowY = showFader ? y + 7 : y + (h - iconSize) / 2

            // Drag handle (reorder grip)
            let gripX = stripWidth + 6
            let gripRect = NSRect(x: gripX, y: rowY, width: iconSize, height: iconSize)
            drawSymbol("line.3.horizontal", in: gripRect, tint: AppTheme.Text.secondary.withAlphaComponent(0.4), config: iconConfig, context: ctx)
            dragHandleRects[i] = gripRect.insetBy(dx: -4, dy: -4)

            // Track label
            let str = NSAttributedString(string: editor.timelineTrackDisplayLabel(at: i), attributes: Self.labelAttrs)
            let labelSize = str.size()
            str.draw(at: NSPoint(x: gripX + iconSize + 6, y: rowY + (iconSize - labelSize.height) / 2))

            let iconY = rowY
            let rightmostX = headerWidth - iconSize - 6

            if isAudio {
                let soloX = rightmostX - iconSize - 4
                let syncX = soloX - iconSize - 4
                syncLockButtonRects[i] = drawToggleIcon(
                    x: syncX, y: iconY, size: iconSize, config: iconConfig, context: ctx,
                    active: track.syncLocked, onSymbol: "link", offSymbol: "personalhotspot.slash"
                )
                soloButtonRects[i] = drawToggleIcon(
                    x: soloX, y: iconY, size: iconSize, config: iconConfig, context: ctx,
                    active: track.soloed, onSymbol: "s.square.fill", offSymbol: "s.square",
                    activeTint: AppTheme.Status.warning
                )
                muteButtonRects[i] = drawToggleIcon(
                    x: rightmostX, y: iconY, size: iconSize, config: iconConfig, context: ctx,
                    active: !track.muted, onSymbol: "speaker.wave.2.fill", offSymbol: "speaker.slash.fill"
                )
                if showFader {
                    drawGainFader(track: track, trackIndex: i, y: y, h: h, context: ctx)
                }
            } else {
                let syncX = rightmostX - iconSize - 4
                syncLockButtonRects[i] = drawToggleIcon(
                    x: syncX, y: iconY, size: iconSize, config: iconConfig, context: ctx,
                    active: track.syncLocked, onSymbol: "link", offSymbol: "personalhotspot.slash"
                )
                hideButtonRects[i] = drawToggleIcon(
                    x: rightmostX, y: iconY, size: iconSize, config: iconConfig, context: ctx,
                    active: !track.hidden, onSymbol: "eye", offSymbol: "eye.slash"
                )
            }

            // White border at top of first track and bottom of every track
            if i == 0 {
                ctx.setFillColor(AppTheme.Border.primary.cgColor)
                ctx.fill(NSRect(x: 0, y: y, width: headerWidth, height: 1))
            }
            let handleY = y + h - 1
            ctx.setFillColor(AppTheme.Border.primary.cgColor)
            ctx.fill(NSRect(x: 0, y: handleY, width: headerWidth, height: 1))
        }

        // Thick divider between the video zone and the audio zone,
        let z = editor.zones
        if z.videoTrackCount > 0, z.audioTrackCount > 0 {
            let dividerY = geo.trackY(at: z.firstAudioIndex)
            ctx.setFillColor(AppTheme.Border.divider.cgColor)
            ctx.fill(NSRect(x: 0, y: dividerY - 1, width: headerWidth, height: 2))
        }
    }

    /// Draw a toggleable SF Symbol button; returns the hit-test rect (padded).
    private func drawToggleIcon(
        x: CGFloat, y: CGFloat, size: CGFloat,
        config: NSImage.SymbolConfiguration, context: CGContext,
        active: Bool, onSymbol: String, offSymbol: String,
        activeTint: NSColor? = nil
    ) -> NSRect {
        let rect = NSRect(x: x, y: y, width: size, height: size)
        let tint = active ? (activeTint ?? AppTheme.Text.secondary) : AppTheme.Text.secondary.withAlphaComponent(0.3)
        drawSymbol(active ? onSymbol : offSymbol, in: rect, tint: tint, config: config, context: context)
        return rect.insetBy(dx: -4, dy: -4)
    }

    // MARK: - Gain fader

    /// Fader groove spans a fixed horizontal band; the dB readout sits to its right.
    private var faderMinX: CGFloat { 11 }
    private var faderMaxX: CGFloat { bounds.width - 32 }

    private func gainDb(forX x: CGFloat) -> Double {
        let t = max(0, min(1, (x - faderMinX) / (faderMaxX - faderMinX)))
        return VolumeScale.floorDb + Double(t) * (VolumeScale.ceilingDb - VolumeScale.floorDb)
    }

    private func gainX(forDb db: Double) -> CGFloat {
        let t = (db - VolumeScale.floorDb) / (VolumeScale.ceilingDb - VolumeScale.floorDb)
        return faderMinX + CGFloat(max(0, min(1, t))) * (faderMaxX - faderMinX)
    }

    private func drawGainFader(track: Track, trackIndex i: Int, y: CGFloat, h: CGFloat, context ctx: CGContext) {
        let grooveY = y + h - 12
        let grooveH: CGFloat = 3
        let db = VolumeScale.dbFromLinear(track.gain)
        let knobX = gainX(forDb: db)

        ctx.setFillColor(AppTheme.Text.muted.cgColor)
        ctx.fill(NSRect(x: faderMinX, y: grooveY, width: faderMaxX - faderMinX, height: grooveH))
        ctx.setFillColor(track.type.themeColor.cgColor)
        ctx.fill(NSRect(x: faderMinX, y: grooveY, width: max(0, knobX - faderMinX), height: grooveH))

        let knobR: CGFloat = 4.5
        ctx.setFillColor(AppTheme.Text.secondary.cgColor)
        ctx.fillEllipse(in: NSRect(x: knobX - knobR, y: grooveY + grooveH / 2 - knobR, width: knobR * 2, height: knobR * 2))

        let rounded = db.rounded()
        let text = track.gain <= 0 || db <= VolumeScale.floorDb ? "-∞" : (rounded == 0 ? "0" : String(format: "%+.0f", rounded))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: AppTheme.FontSize.xxs, weight: .medium),
            .foregroundColor: AppTheme.Text.tertiary,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: bounds.width - 6 - sz.width, y: grooveY + grooveH / 2 - sz.height / 2))

        gainFaderRects[i] = NSRect(x: faderMinX - knobR, y: grooveY - 6, width: (faderMaxX - faderMinX) + knobR * 2, height: 15)
    }

    private func drawSymbol(_ name: String, in rect: NSRect, tint: NSColor, config: NSImage.SymbolConfiguration, context: CGContext) {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let symbolSize = img.size
        let drawRect = NSRect(x: rect.midX - symbolSize.width / 2, y: rect.midY - symbolSize.height / 2, width: symbolSize.width, height: symbolSize.height)
        let tinted = NSImage(size: drawRect.size, flipped: true) { drawRect in
            tint.set()
            img.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            drawRect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    // MARK: - Input handling (mute/hide/resize)

    private var resizeDrag: (trackIndex: Int, originalHeight: CGFloat)?
    private var reorderDrag: (id: String, before: Timeline)?
    private var gainDrag: (trackIndex: Int, before: Timeline)?

    private func applyGainDrag(trackIndex: Int, atX x: CGFloat) {
        let db = gainDb(forX: x)
        let linear = db <= VolumeScale.floorDb ? 0 : VolumeScale.linearFromDb(db)
        editor.setTrackGainLive(trackIndex: trackIndex, gain: linear)
    }

    private func hitTestResizeHandle(at point: NSPoint) -> Int? {
        let geo = TimelineGeometry(editor: editor, bounds: bounds)
        for i in editor.timeline.tracks.indices {
            let trackBottom = geo.trackY(at: i) + geo.trackHeight(at: i)
            if abs(point.y - trackBottom) <= TrackSize.resizeHandleZone {
                return i
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        for (ti, rect) in muteButtonRects {
            if rect.contains(point) {
                editor.toggleTrackMute(trackIndex: ti)
                needsDisplay = true
                return
            }
        }
        for (ti, rect) in soloButtonRects {
            if rect.contains(point) {
                editor.toggleTrackSolo(trackIndex: ti)
                needsDisplay = true
                return
            }
        }
        for (ti, rect) in hideButtonRects {
            if rect.contains(point) {
                editor.toggleTrackHidden(trackIndex: ti)
                needsDisplay = true
                return
            }
        }
        for (ti, rect) in syncLockButtonRects {
            if rect.contains(point) {
                editor.toggleTrackSyncLock(trackIndex: ti)
                needsDisplay = true
                return
            }
        }
        for (ti, rect) in gainFaderRects {
            if rect.contains(point) {
                if event.clickCount == 2 {
                    editor.resetTrackGain(trackIndex: ti)
                } else {
                    gainDrag = (ti, editor.timeline)
                    applyGainDrag(trackIndex: ti, atX: point.x)
                }
                needsDisplay = true
                return
            }
        }

        for (ti, rect) in dragHandleRects {
            if rect.contains(point) {
                reorderDrag = (editor.timeline.tracks[ti].id, editor.timeline)
                NSCursor.closedHand.set()
                return
            }
        }

        if let ti = hitTestResizeHandle(at: point) {
            resizeDrag = (ti, editor.timeline.tracks[ti].displayHeight)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let drag = gainDrag {
            applyGainDrag(trackIndex: drag.trackIndex, atX: point.x)
            needsDisplay = true
            return
        }

        if let drag = reorderDrag {
            let geo = TimelineGeometry(editor: editor, bounds: bounds)
            editor.reorderTrackLive(id: drag.id, to: geo.trackAt(y: Double(point.y)))
            NSCursor.closedHand.set()
            needsDisplay = true
            requestCanvasRedraw?()
            return
        }

        guard let drag = resizeDrag else { return }
        let geo = TimelineGeometry(editor: editor, bounds: bounds)
        let trackTop = geo.trackY(at: drag.trackIndex)
        let newHeight = max(TrackSize.minHeight, min(TrackSize.maxHeight, point.y - trackTop))
        if editor.timeline.tracks[drag.trackIndex].displayHeight != newHeight {
            editor.timeline.tracks[drag.trackIndex].displayHeight = newHeight
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let drag = gainDrag {
            gainDrag = nil
            editor.commitTrackGain(trackIndex: drag.trackIndex, before: drag.before)
            needsDisplay = true
            return
        }

        if let drag = reorderDrag {
            reorderDrag = nil
            editor.commitTrackReorder(before: drag.before)
            needsDisplay = true
            return
        }

        guard let drag = resizeDrag else { return }
        let finalHeight = editor.timeline.tracks[drag.trackIndex].displayHeight
        if finalHeight != drag.originalHeight {
            editor.timeline.tracks[drag.trackIndex].displayHeight = drag.originalHeight
            editor.setTrackHeight(trackIndex: drag.trackIndex, height: finalHeight)
        }
        resizeDrag = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if dragHandleRects.values.contains(where: { $0.contains(point) }) {
            NSCursor.openHand.set()
        } else if hitTestResizeHandle(at: point) != nil {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }
}
