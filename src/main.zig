const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const Global = struct {
    pool: *pg.Pool,
};

const CreateTransactionReturn = enum(i32) { NotFound = 1, LimitExceeded = 2 };

const TransactionPayload = struct { valor: i64, tipo: []const u8, descricao: []const u8 };
const TransactionStatement = struct { valor: i64, tipo: []const u8, descricao: []const u8, realizado_em: i64 };

pub fn main() !void {
    const port_env = std.os.getenv("PORT") orelse "3000";
    const PORT = try std.fmt.parseInt(u16, port_env, 10);

    const pool = try pg.Pool.init(allocator, .{
        .size = 10,
        .connect = .{
            .port = 5432,
            .host = "127.0.0.1",
        },
        .auth = .{ .username = "user", .password = "password", .database = "db", .timeout = 10_000 },
    });

    const global = Global{ .pool = pool };
    var server = try httpz.ServerCtx(Global, Global).init(allocator, .{ .port = PORT }, global);
    var router = server.router();

    router.get("/clientes/:id/extrato", extrato);
    router.post("/clientes/:id/transacoes", transacoes);

    try server.listen();
}

fn extrato(global: Global, req: *httpz.Request, res: *httpz.Response) !void {
    const id_param = req.param("id").?;
    const id = std.fmt.parseInt(i32, id_param, 10) catch return;

    if (id < 1 or id > 5) {
        res.status = 404;
        return;
    }

    var result = try global.pool.query("SELECT saldo, limite FROM cliente WHERE id = $1", .{id});
    defer result.deinit();

    const row = try result.next();
    const saldo = row.?.get(i32, 0);
    const limite = row.?.get(i32, 1);
    const realizado_em = std.time.timestamp();

    result = try global.pool.query("SELECT valor, tipo, descricao, realizado_em FROM Transacao WHERE cliente_id = $1 ORDER BY realizado_em DESC LIMIT 10", .{id});

    var ultimas_trasacoes = std.ArrayList(TransactionStatement).init(allocator);

    while (try result.next()) |row_transaction| {
        try ultimas_trasacoes.append(TransactionStatement{
            .valor = row_transaction.get(i32, 0),
            .tipo = row_transaction.get([]u8, 1),
            .descricao = row_transaction.get([]u8, 2),
            .realizado_em = row_transaction.get(i64, 3),
        });
    }

    try res.json(.{ .saldo = .{
        .total = saldo,
        .limite = limite,
        .data_extrato = realizado_em,
    }, .ultimas_trasacoes = ultimas_trasacoes.items[0..] }, .{});
}

fn transacoes(global: Global, req: *httpz.Request, res: *httpz.Response) !void {
    const id_param = req.param("id").?;
    const id = std.fmt.parseInt(i32, id_param, 10) catch return;

    if (id < 1 or id > 5) {
        res.status = 404;
        return;
    }

    const body = req.json(TransactionPayload) catch {
        res.status = 422;
        return;
    };

    if (body) |payload| {
        if ((payload.tipo.len != 1 or (payload.tipo[0] != 'd' and payload.tipo[0] != 'c')) or
            (payload.descricao.len <= 0 or payload.descricao.len > 10))
        {
            res.status = 400;
            return;
        }

        var valor = payload.valor;
        if (payload.tipo[0] == 'd') valor *= -1;

        var result = try global.pool.query("select criartransacao($1, $2, $3, $4);", .{ id, valor, payload.tipo, payload.descricao });
        defer result.deinit();

        const row = try result.next();
        const raw = row.?.get([]u8, 0);

        // First byte indicates how many items we have in the record
        const len = std.mem.readInt(i32, raw[0..4], .big);

        if (len == 1) {
            // Don't really care for the next two bytes, the value is in [12..16]
            const status_value = std.mem.readInt(i32, raw[12..16], .big);
            const status: CreateTransactionReturn = @enumFromInt(status_value);

            switch (status) {
                CreateTransactionReturn.NotFound => {
                    res.status = 404;
                    return;
                },
                CreateTransactionReturn.LimitExceeded => {
                    res.status = 422;
                    return;
                },
            }
        }

        // If len is not 1 we expect two values so...
        const saldo = std.mem.readInt(i32, raw[12..16], .big);
        // We have more two bytes that we don't care here so...
        const limite = std.mem.readInt(i32, raw[24..28], .big);
        try res.json(.{ .saldo = saldo, .limite = limite }, .{});
        return;
    } else {
        res.status = 422;
        return;
    }
}
