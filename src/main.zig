const std = @import("std");
const zap = @import("zap");

fn on_request(r: zap.Request) void {
    if (r.path) |path| {
        const base = "/clientes";
        if (std.mem.eql(u8, path[0..base.len], base)) {
            var id: u8 = undefined;
            var target: []const u8 = undefined;

            var iter = std.mem.tokenize(u8, path, "/");

            _ = iter.next(); //skip base

            if (iter.next()) |_id| {
                id = std.fmt.parseInt(u8, _id, 10) catch return; // hadle error
            }

            if (iter.next()) |_target| {
                target = _target;
            }

            call_handlder(target, id, r);
        }
    }
}

pub fn call_handlder(target: []const u8, id: u8, r: zap.Request) void {
    if (std.mem.eql(u8, target, "transacoes")) {
        transactions(id, r);
    } else if (std.mem.eql(u8, target, "extrato")) {
        statment(id, r);
    } else {
        r.setStatus(zap.StatusCode.not_found);
        r.sendBody("") catch return;
    }
}

pub fn statment(id: u8, r: zap.Request) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();

    const T = struct { id: u8 };

    std.json.stringify(T{ .id = id }, .{}, response.writer()) catch return;

    const res: []const u8 = response.items[0..];

    r.setContentType(.JSON) catch return;
    r.sendBody(res) catch return;
}

pub fn transactions(id: u8, r: zap.Request) void {
    _ = id;
    r.sendBody("transacoes") catch return;
}

pub fn main() !void {
    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = on_request,
        .log = false,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    // start worker threads
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}
