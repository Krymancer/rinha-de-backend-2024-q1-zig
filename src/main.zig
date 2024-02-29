const std = @import("std");
const zap = @import("zap");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

const Transaction = struct { valor: u32, tipo: []const u8, descricao: []const u8, realizada_em: i64 };
const Statment = struct { total: i64, data_extrato: i64, limite: u32 };
const Client = struct { saldo: i64, limite: u32, transactions: std.ArrayList(Transaction) };

const TransactionPayload = struct { valor: u32, tipo: []const u8, descricao: []const u8 };
const TransactionResponse = struct { saldo: i64, limite: u32 };
const StatmentReponse = struct { saldo: Statment, ultimas_transacoes: []Transaction };

var clients = std.AutoHashMap(u8, Client).init(allocator);

fn on_request(r: zap.Request) void {
    if (r.path) |path| {
        const base = "/clientes";
        if (std.mem.eql(u8, path[0..base.len], base)) {
            var id: u8 = undefined;
            var target: []const u8 = undefined;

            var iter = std.mem.tokenize(u8, path, "/");

            _ = iter.next();

            if (iter.next()) |_id| {
                id = std.fmt.parseInt(u8, _id, 10) catch return;
            }

            if (iter.next()) |_target| {
                target = _target;
            }

            if (id == undefined) {
                r.setStatus(zap.StatusCode.not_found);
                r.sendBody("") catch return;
            }

            if (target.len == 0) {
                r.setStatus(zap.StatusCode.not_found);
                r.sendBody("") catch return;
            }

            if (id < 1 or id > 5) {
                r.setStatusNumeric(404);
                return;
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
    const client = clients.get(id);

    if (client) |cli| {
        const saldo = Statment{
            .limite = cli.limite,
            .total = cli.saldo,
            .data_extrato = std.time.timestamp(),
        };

        const count = cli.transactions.items.len;

        var total: usize = 10;

        if (count < total) total = count;

        const ultimas_transacoes = cli.transactions.items[0..total];

        const res = StatmentReponse{
            .saldo = saldo,
            .ultimas_transacoes = ultimas_transacoes,
        };

        var response = std.ArrayList(u8).init(allocator);
        defer response.deinit();
        std.json.stringify(res, .{}, response.writer()) catch return;

        r.setContentType(.JSON) catch return;
        r.sendBody(response.items[0..]) catch return;
        return;
    }
}

pub fn transactions(id: u8, r: zap.Request) void {
    if (r.method) |method| {
        if (std.mem.eql(u8, method, "POST")) {
            if (r.body) |body| {
                const parsed = std.json.parseFromSlice(TransactionPayload, allocator, body, .{}) catch {
                    r.setStatusNumeric(422);
                    r.sendBody("error parsing json") catch return;
                    std.debug.print("error parsing json", .{});
                    return;
                };

                defer parsed.deinit();

                const request = parsed.value;

                // Validation
                var isValid = true;
                if (request.valor < 0) isValid = false;
                if (request.tipo.len > 1) isValid = false;
                if ((request.tipo[0] != 'd') and (request.tipo[0] != 'c')) isValid = false;
                if ((request.descricao.len > 10) or (request.descricao.len < 1)) isValid = false;

                if (!isValid) {
                    r.setStatusNumeric(422);
                    r.sendBody("") catch return;
                    std.debug.print("invalid request {d} {s} {s}", .{ request.valor, request.tipo, request.descricao });
                    return;
                }

                var valor: i64 = request.valor;

                if (std.mem.eql(u8, request.tipo, "d")) {
                    valor *= -1;
                }

                var client = clients.get(id);

                if (client) |cli| {
                    if (@abs(cli.saldo + valor) > cli.limite) {
                        r.setStatusNumeric(422);
                        std.debug.print("insuficient limit {d} {d} {d}", .{ cli.saldo, valor, cli.limite });
                        return;
                    } else {
                        client.?.saldo += valor;
                        client.?.transactions.append(Transaction{
                            .tipo = request.tipo,
                            .descricao = request.descricao,
                            .valor = request.valor,
                            .realizada_em = std.time.timestamp(),
                        }) catch return;

                        clients.put(id, client.?) catch return;

                        var response = std.ArrayList(u8).init(allocator);
                        defer response.deinit();

                        std.json.stringify(TransactionResponse{ .saldo = client.?.saldo, .limite = cli.limite }, .{}, response.writer()) catch return;

                        r.setStatusNumeric(200);
                        r.setContentType(.JSON) catch return;
                        r.sendBody(response.items[0..]) catch return;
                        return;
                    }
                }
            } else {
                r.setStatus(zap.StatusCode.bad_request);
                r.sendBody("") catch return;
                return;
            }
        } else {
            r.setStatus(zap.StatusCode.method_not_allowed);
            r.sendBody("") catch return;
            return;
        }
    } else {
        r.sendBody("") catch return;
        return;
    }
}

pub fn main() !void {
    clients.put(1, Client{ .limite = 100000, .saldo = 0, .transactions = std.ArrayList(Transaction).init(allocator) }) catch return;
    clients.put(2, Client{ .limite = 80000, .saldo = 0, .transactions = std.ArrayList(Transaction).init(allocator) }) catch return;
    clients.put(3, Client{ .limite = 1000000, .saldo = 0, .transactions = std.ArrayList(Transaction).init(allocator) }) catch return;
    clients.put(4, Client{ .limite = 10000000, .saldo = 0, .transactions = std.ArrayList(Transaction).init(allocator) }) catch return;
    clients.put(5, Client{ .limite = 500000, .saldo = 0, .transactions = std.ArrayList(Transaction).init(allocator) }) catch return;

    var listener = zap.HttpListener.init(.{
        .port = 3000,
        .on_request = on_request,
        .log = false,
    });
    try listener.listen();

    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}
