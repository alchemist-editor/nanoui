//! A field focused with all its text selected from the very first frame
//! a window draws (`ui.focusNext(c, true)`): a dialog opening onto its
//! value (a clip speed, a rename) types over it at once, and the focus
//! stays once the app stops asking.
const std = @import("std");
const testing = std.testing;
const ui = @import("ui.zig");

const Dialog = struct {
    buf: ui.TextBuffer = .{},
    frames: u32 = 0,
    fn view(s: *Dialog, c: *ui.Context) void {
        ui.column(c, .{ .padding = .all(16), .gap = 8 });
        defer ui.end(c);
        ui.text(c, "Speed", .{});
        if (s.frames == 0) ui.focusNext(c, true);
        s.frames += 1;
        _ = ui.textField(c, &s.buf, .{ .placeholder = "Percent" });
    }
};

test "focusNext(c, true) on the first frame focuses the field with all its text selected" {
    var s: Dialog = .{};
    defer s.buf.deinit();
    s.buf.set("100%");
    var t: ui.Tester = undefined;
    // `init` runs the first frame: nothing else happens before the check.
    try t.init(testing.allocator, .init(&s, Dialog.view), .{ .width = 300, .height = 120 });
    defer t.deinit();
    const f = t.ctx.focused_text orelse return error.NotFocused;
    try testing.expectEqualStrings("100%", f.text);
    try testing.expectEqual(@as(usize, 0), @min(f.caret, f.anchor));
    try testing.expectEqual(@as(usize, 4), @max(f.caret, f.anchor));
    // Later frames keep it focused, the selection intact.
    t.frame();
    t.frame();
    try testing.expect(t.ctx.focused_text != null);
    t.typeText("50");
    try testing.expectEqualStrings("50", s.buf.text());
}
