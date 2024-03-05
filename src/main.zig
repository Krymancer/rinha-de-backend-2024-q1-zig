const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");

var pool: *pg.Pool = undefined;

const CreateTransactionReturn = enum(i32) { NotFound = 1, LimitExceeded = 2 };
const TransactionPayload = struct { valor: i64, tipo: []const u8, descricao: []const u8 };
const TransactionStatement = struct { valor: i64, tipo: []const u8, descricao: []const u8, realizado_em: i64 };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const port_env = std.os.getenv("PORT") orelse "3000";
    const PORT = try std.fmt.parseInt(u16, port_env, 10);

    pool = try pg.Pool.init(allocator, .{
        .size = 10,
        .connect = .{
            .port = 5432,
            .host = "127.0.0.1",
        },
        .auth = .{ .username = "user", .password = "password", .database = "db" },
    });
    defer pool.deinit();

    var server = try httpz.Server().init(allocator, .{ .port = PORT });
    var router = server.router();

    router.get("/clientes/:id/extrato", extrato);
    router.post("/clientes/:id/transacoes", transacoes);

    try server.listen();
}

fn extrato(req: *httpz.Request, res: *httpz.Response) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const id_param = req.param("id").?;
    const id = std.fmt.parseInt(i32, id_param, 10) catch return;

    if (id < 1 or id > 5) {
        res.status = 404;
        return;
    }

    var result = try pool.query("SELECT saldo, limite FROM cliente WHERE id = $1", .{id});
    defer result.deinit();

    const row = try result.next() orelse {
        res.status = 404;
        return;
    };

    const saldo = row.get(i32, 0);
    const limite = row.get(i32, 1);
    const realizado_em = std.time.timestamp();

    var result_trans = try pool.query("SELECT valor, tipo, descricao, realizado_em FROM Transacao WHERE cliente_id = $1 ORDER BY realizado_em DESC LIMIT 10", .{id});
    defer result_trans.deinit();

    var ultimas_transacoes = std.ArrayList(TransactionStatement).init(allocator);
    defer ultimas_transacoes.deinit();

    while (try result_trans.next()) |row_transaction| {
        try ultimas_transacoes.append(TransactionStatement{
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
    }, .ultimas_transacoes = ultimas_transacoes.items[0..] }, .{});
    return;
}

fn transacoes(req: *httpz.Request, res: *httpz.Response) !void {
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
            res.status = 422;
            return;
        }

        var valor = payload.valor;
        if (payload.tipo[0] == 'd') valor *= -1;

        var row = try pool.row("select criartransacao($1, $2, $3, $4);", .{ id, valor, payload.tipo, payload.descricao }) orelse {
            res.status = 500;
            return;
        };
        defer row.deinit();

        var record = row.record(0);

        if (record.number_of_columns == 1) {
            const status_value = record.next(i32);
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

        const saldo = record.next(i32);
        const limite = record.next(i32);
        try res.json(.{ .saldo = saldo, .limite = limite }, .{});
        return;
    } else {
        res.status = 422;
        return;
    }
}
