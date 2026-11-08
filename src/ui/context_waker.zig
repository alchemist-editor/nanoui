//! A frame asked for from any thread (a decoder's, a worker's): the context
//! names who draws its frames (the window's surface, or a Tester), and any
//! thread may wake it.
const Context = @import("context.zig").Context;

pub const Waker = struct { ctx: *anyopaque, wake: *const fn (ctx: *anyopaque) void };

/// A frame is wanted, drawn at the display's next refresh. Lock-free; many
/// asks before it runs are one frame. Not after the window has closed.
pub fn requestFrameFromAnyThread(c: *const Context) void {
    if (c.waker) |w| w.wake(w.ctx);
}
