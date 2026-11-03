import AppKit
import RiveRuntime

/// A RiveView that never tracks the mouse. RiveView adds a new tracking area
/// every time AppKit asks it to update them, without removing the last one;
/// this view moves every frame, so they pile up and AppKit walks them all on
/// every mouse move. The spider gets the pointer from the view model anyway,
/// and its window ignores the mouse.
final class SpiderView: RiveView {
    override func updateTrackingAreas() {}
}
