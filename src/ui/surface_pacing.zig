//! The macOS surface's pace: the display link's frame-rate cap (an app's,
//! under the screen's own), and how a live resize's steps are drawn (in the
//! window's transaction, or by the link while the drag moves).
const std = @import("std");
const objc = @import("../objc.zig");
const cf = @import("cf.zig");
const Surface = @import("surface.zig").Surface;

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

pub fn updateMaxFps(self: *Surface) void {
    const screen = objc.msg(?objc.Object, self.window.nswindow, "screen", .{});
    const screen_fps: f32 = if (screen) |sc| @floatFromInt(@max(60, objc.msg(objc.NSInteger, sc, "maximumFramesPerSecond", .{}))) else 60;
    const fps = if (self.fps_cap > 0) @min(self.fps_cap, screen_fps) else screen_fps;
    if (fps != self.max_fps) {
        self.max_fps = fps;
        const cur = self.link_fps;
        self.link_fps = -1;
        if (cur >= 0) self.setRate(if (cur == 0) null else 1 / cur);
    }
}

/// Caps the display link's pace at `fps` (0 lifts the cap).
pub fn setFpsCap(self: *Surface, fps: f32) void {
    self.fps_cap = fps;
    self.updateMaxFps();
}

/// How long the link keeps running after a live-resize step: a drag's
/// next step lands on a running link, and a held mouse stops it.
const resize_grace = 0.25;

/// A live resize is changing the size now: a held mouse is not.
pub fn resizeStepping(self: *Surface) bool {
    return self.ctx.live_resizing and cf.CACurrentMediaTime() - self.resize_step_at < resize_grace;
}

/// One live-resize step drawn in the window's own transaction: the
/// frame is laid out and presented at this size before Core Animation
/// composites the step, so the window never shows a stale one. False
/// when it can't (hidden, or `NANOUI_RESIZE_SYNC=0`): the link draws.
pub fn resizeSyncEnabled(_: *Surface) bool {
    if (getenv("NANOUI_RESIZE_SYNC")) |v| if (std.mem.eql(u8, std.mem.span(v), "0")) return false;
    return true;
}

pub fn resizeInTransaction(self: *Surface) bool {
    if (self.in_frame or self.dead or !self.visible() or self.display_link != null) return false;
    if (!self.resizeSyncEnabled()) return false;
    const drawable = objc.msg(?objc.Object, self.renderer.layer, "nextDrawable", .{}) orelse return false;
    self.renderer.given_drawable = drawable;
    defer self.renderer.given_drawable = null;
    self.pending_sync = true;
    self.full_pending = true;
    const now = @max(cf.CACurrentMediaTime(), self.last_frame_time);
    const fallback_dur = 1.0 / @as(f64, @max(60.0, self.max_fps));
    self.frameAt(.input, now, if (self.link_duration > 0) self.link_duration else fallback_dur);
    return true;
}
