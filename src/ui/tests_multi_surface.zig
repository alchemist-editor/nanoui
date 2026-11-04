//! Two views at once, each with its own Tester (a main window and a
//! floating panel's): both draw with the one Metal device, so a texture
//! made for the first (an app's MTLTexture, a decoder's CVPixelBuffer)
//! draws the same in the second's offscreen render.
const std = @import("std");
const testing = std.testing;
const ui = @import("ui.zig");
const text = @import("text.zig");

const n = 32;

const Scene = struct {
    source: ui.Texture,
    label: []const u8,
    fn view(s: *Scene, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull();
        defer root.end();
        ui.texture(c, .{ .width = .{ .px = n }, .height = .{ .px = n } }, s.source, .{ 0, 0, 1, 1 }, 1);
        ui.text(c, s.label, .{ .size = 11 });
    }
};

fn pixel(p: @import("gpu.zig").Pixels, x: usize, y: usize) [4]u8 {
    return p.bytes[(y * p.width + x) * 4 ..][0..4].*;
}

extern "c" fn CVPixelBufferCreate(allocator: ?*anyopaque, width: usize, height: usize, format: u32, attrs: ?*anyopaque, out: *?*anyopaque) i32;
extern "c" fn CVPixelBufferLockBaseAddress(pb: *anyopaque, flags: u64) i32;
extern "c" fn CVPixelBufferUnlockBaseAddress(pb: *anyopaque, flags: u64) i32;
extern "c" fn CVPixelBufferGetBaseAddress(pb: *anyopaque) ?[*]u8;
extern "c" fn CVPixelBufferGetBytesPerRow(pb: *anyopaque) usize;
extern "c" fn CFRelease(obj: *anyopaque) void;
extern "c" const kCVPixelBufferMetalCompatibilityKey: *anyopaque;
extern "c" const kCVPixelBufferIOSurfacePropertiesKey: *anyopaque;

test "a texture made for surface 1 draws in surface 2's offscreen render" {
    if (text.portable) return error.SkipZigTest;
    const objc = @import("../objc.zig");
    const gpa = testing.allocator;
    const device: objc.Object = @ptrCast(ui.metalDevice() orelse return error.SkipZigTest);

    // An app's BGRA texture on the shared device: orange.
    var px: [n * n * 4]u8 = undefined;
    for (0..n * n) |i| px[i * 4 ..][0..4].* = .{ 0x20, 0x80, 0xf0, 0xff };
    const desc = objc.msg(objc.Object, objc.class("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", .{ @as(objc.NSUInteger, 80), @as(objc.NSUInteger, n), @as(objc.NSUInteger, n), objc.NO });
    const tex = objc.msg(objc.Object, device, "newTextureWithDescriptor:", .{desc});
    defer objc.release(tex);
    const MTLRegion = extern struct { x: objc.NSUInteger = 0, y: objc.NSUInteger = 0, z: objc.NSUInteger = 0, w: objc.NSUInteger, h: objc.NSUInteger, d: objc.NSUInteger = 1 };
    objc.msg(void, tex, "replaceRegion:mipmapLevel:withBytes:bytesPerRow:", .{ MTLRegion{ .w = n, .h = n }, @as(objc.NSUInteger, 0), @as(*const anyopaque, &px), @as(objc.NSUInteger, n * 4) });

    var a: Scene = .{ .source = .{ .width = n, .height = n, .mtl_texture = @ptrCast(tex) }, .label = "main" };
    var b: Scene = .{ .source = a.source, .label = "float" };
    var t1: ui.Tester = undefined;
    try t1.init(gpa, .init(&a, Scene.view), .{ .width = 64, .height = 64, .scale = 1 });
    defer t1.deinit();
    var t2: ui.Tester = undefined;
    try t2.init(gpa, .init(&b, Scene.view), .{ .width = 80, .height = 48, .scale = 1 });
    defer t2.deinit();
    try testing.expectEqual(@as(*anyopaque, @ptrCast(t1.renderer.device)), @as(*anyopaque, @ptrCast(t2.renderer.device)));
    try testing.expectEqual(ui.metalDevice().?, @as(*anyopaque, @ptrCast(t2.renderer.device)));
    t1.settle(0.1);
    t2.settle(0.1);
    try testing.expect(t1.hasText("main") and !t1.hasText("float"));
    try testing.expect(t2.hasText("float") and !t2.hasText("main"));
    const r1 = try t1.render(gpa);
    defer r1.deinit(gpa);
    const r2 = try t2.render(gpa);
    defer r2.deinit(gpa);
    try testing.expectEqual(pixel(r1, 16, 16), pixel(r2, 16, 16));
    const p = pixel(r2, 16, 16);
    try testing.expect(p[2] > 0xd0 and p[1] > 0x60 and p[1] < 0xa0 and p[0] < 0x40);

    // A CVPixelBuffer shown in both: wrapped by each surface's own cache.
    const keys = [2]*anyopaque{ kCVPixelBufferMetalCompatibilityKey, kCVPixelBufferIOSurfacePropertiesKey };
    const values = [2]objc.Object{ objc.msg(objc.Object, objc.class("NSNumber"), "numberWithBool:", .{objc.YES}), objc.msg(objc.Object, objc.class("NSDictionary"), "dictionary", .{}) };
    const attrs = objc.msg(objc.Object, objc.class("NSDictionary"), "dictionaryWithObjects:forKeys:count:", .{ @as(*const anyopaque, &values), @as(*const anyopaque, &keys), @as(objc.NSUInteger, 2) });
    var pb: ?*anyopaque = null;
    try testing.expectEqual(@as(i32, 0), CVPixelBufferCreate(null, n, n, std.mem.readInt(u32, "BGRA", .big), @ptrCast(attrs), &pb));
    defer CFRelease(pb.?);
    _ = CVPixelBufferLockBaseAddress(pb.?, 0);
    const base = CVPixelBufferGetBaseAddress(pb.?).?;
    const stride = CVPixelBufferGetBytesPerRow(pb.?);
    for (0..n) |y| for (0..n) |x| {
        base[y * stride + x * 4 ..][0..4].* = .{ 0xe0, 0x40, 0x20, 0xff };
    };
    _ = CVPixelBufferUnlockBaseAddress(pb.?, 0);
    a.source = .{ .width = n, .height = n, .pixel_buffer = pb };
    b.source = a.source;
    t1.settle(0.1);
    t2.settle(0.1);
    const v1 = try t1.render(gpa);
    defer v1.deinit(gpa);
    const v2 = try t2.render(gpa);
    defer v2.deinit(gpa);
    try testing.expectEqual(pixel(v1, 16, 16), pixel(v2, 16, 16));
    try testing.expect(pixel(v2, 16, 16)[0] > 0xc0);
}
