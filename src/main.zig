const std = @import("std");
const httpz = @import("httpz");

const TransactionPayload = struct { valor: u32, tipo: []const u8, descricao: []const u8 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server().init(allocator, .{ .port = 3000 });
    var router = server.router();

    router.get("/clientes/:id/extrato", extrato);
    router.post("/clientes/:id/transacoes", transacoes);

    try server.listen();
}

fn extrato(req: *httpz.Request, res: *httpz.Response) !void {
    try res.json(.{ .id = req.param("id").?, .name = "Teg" }, .{});
}

fn transacoes(req: *httpz.Request, res: *httpz.Response) !void {
    const id = req.param("id");
    const body = req.json(TransactionPayload) catch {
        res.status = 422;
        return;
    };

    if (body) |payload| {
        try res.json(.{ .id = id, .valor = payload.valor, .tipo = payload.tipo, .descricao = payload.descricao }, .{});
        return;
    } else {
        res.status = 422;
        return;
    }
}
