const std = @import("std");
const Io = std.Io;

const Assignment_4 = @import("Assignment_4");

const Edge = struct {
    to: u32,
    weight: f32,
    name: []const u8,
};

const Node = struct {
    edges: std.ArrayList(Edge),
};

const Graph = struct {
    nodes: []Node,
};

const PQItem = struct {
    node: u32,
    dist: f32,
};

fn lessThan(_: void, a: PQItem, b: PQItem) std.math.Order {
    if (a.dist < b.dist) return .lt;
    if (a.dist > b.dist) return .gt;
    return .eq;
}

//-----------------------------
// Name -> ID Helper
//-----------------------------
fn loadPlaceNames(
    allocator: std.mem.Allocator,
    io: Io,
    filename: []const u8,
    id_to_name: []?[]const u8,
) !void {
    var file = try Io.Dir.cwd().openFile(io, filename, .{});
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    const interface = &reader.interface;

    while (true) {
        const maybe_line = interface.takeDelimiter('\n') catch |err| return err;

        if (maybe_line == null) break;

        const line = maybe_line.?;

        var it = std.mem.splitScalar(u8, line, ',');

        const id_str = it.next() orelse continue;
        const raw_name = it.next() orelse continue;
        const name = std.mem.trim(u8, raw_name, " \r\n\t");

        const id = try std.fmt.parseInt(u32, id_str, 10);

        id_to_name[id] = try allocator.dupe(u8, name);
    }
}

fn buildNameToIdMap(
    allocator: std.mem.Allocator,
    io: Io,
    filename: []const u8,
    name_to_id: *std.StringHashMap(std.ArrayList(u32)),
) !void {
    var file = try Io.Dir.cwd().openFile(io, filename, .{});
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    const interface = &reader.interface;

    while (true) {
        const maybe_line = interface.takeDelimiter('\n') catch |err| return err;

        if (maybe_line == null) break;

        const line = maybe_line.?;

        var it = std.mem.splitScalar(u8, line, ',');

        const id_str = it.next() orelse continue;
        const raw_name = it.next() orelse continue;
        const name = std.mem.trim(u8, raw_name, " \r\n\t");

        const id = try std.fmt.parseInt(u32, id_str, 10);

        if(name_to_id.getPtr(name)) |list_ptr| {
            try list_ptr.append(allocator, id);
        } else {
            var list = std.ArrayList(u32).empty;
            try list.append(allocator, id);
            const owned = try allocator.dupe(u8, name);
            try name_to_id.put(owned, list);
        }
    }
}

//-----------------------------
// First pass: count + map IDS
//-----------------------------
fn findMaxId(io: Io, filename: []const u8) !u32 {
    var file = try Io.Dir.cwd().openFile(io, filename, .{});
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    const interface = &reader.interface;

    var max_id: u32 = 0;
    while (true) {
        const maybe_line = interface.takeDelimiter('\n') catch |err| return err;

        if (maybe_line == null) break;

        const line = maybe_line.?;

        var it = std.mem.splitScalar(u8, line, ',');

        const a_str = it.next() orelse continue;
        const b_str = it.next() orelse continue;

        const a = try std.fmt.parseInt(u32, a_str, 10);
        const b = try std.fmt.parseInt(u32, b_str, 10);

        if (a > max_id) max_id = a;
        if (b > max_id) max_id = b;
    }

    return max_id;
}

//-----------------------------
// Second pass: build graph
//-----------------------------
fn buildGraph(
    allocator: std.mem.Allocator,
    io: Io,
    filename: []const u8,
    graph: *Graph,
) !void {
    var file = try Io.Dir.cwd().openFile(io, filename, .{});
    defer file.close(io);

    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(io, &reader_buf);
    const interface = &reader.interface;

    while (true) {
        const maybe_line = interface.takeDelimiter('\n') catch |err| return err;

        if (maybe_line == null) break;

        const line = maybe_line.?;

        var it = std.mem.splitScalar(u8, line, ',');

        const a_str = it.next() orelse continue;
        const b_str = it.next() orelse continue;
        const weight_str = it.next() orelse continue;
        const road_name_raw = it.next() orelse "";
        const road_name = std.mem.trim(u8, road_name_raw, " \r\n\t");

        const a = try std.fmt.parseInt(u32, a_str, 10);
        const b = try std.fmt.parseInt(u32, b_str, 10);
        const weight = try std.fmt.parseFloat(f32, weight_str);
        const owned_name = try allocator.dupe(u8, road_name);

        try graph.nodes[a].edges.append(allocator, .{
            .to = b,
            .weight = weight,
            .name = owned_name,
        });

        // If undirected, also add reverse
        try graph.nodes[b].edges.append(allocator, .{
            .to = a,
            .weight = weight,
            .name = owned_name,
        });
    }
}

//-----------------------------
// Dijkstra
//-----------------------------
fn dijkstra(
    allocator: std.mem.Allocator,
    graph: *Graph,
    start: u32,
) !struct {
    dist: []f32,
    prev: []?u32,
} {
    const n = graph.nodes.len;

    var dist = try allocator.alloc(f32, n);
    var prev = try allocator.alloc(?u32, n);

    for (dist) |*d| d.* = std.math.inf(f32);
    for (prev) |*p| p.* = null;

    dist[start] = 0;

    var pq = std.PriorityQueue(PQItem, void, lessThan).initContext({});
    defer pq.deinit(allocator);

    try pq.push(allocator, .{ .node = start, .dist = 0 });

    while (pq.pop()) |item| {
        const u = item.node;

        if (item.dist > dist[u]) continue;

        for (graph.nodes[u].edges.items) |edge| {
            const alt = dist[u] + edge.weight;

            if (alt < dist[edge.to]) {
                dist[edge.to] = alt;
                prev[edge.to] = u;

                try pq.push(allocator, .{
                    .node = edge.to,
                    .dist = alt,
                });
            }
        }
    }

    return .{ .dist = dist, .prev = prev };
}

//---------------------------------------------
// Helper function for searching for
// minimum id (since there are duplicates)
//---------------------------------------------
fn pickMinId(list: std.ArrayList(u32)) u32 {
    var min = list.items[0];
    for (list.items[1..]) |id| {
        if (id < min) min = id;
    }
    return min;
}

//-----------------------------
// Path Reconstruction
//-----------------------------
fn reconstructPath(
    allocator: std.mem.Allocator,
    prev: []?u32,
    target: u32,
) ![]u32 {
    var path: std.ArrayList(u32) = .empty;

    var current: ?u32 = target;

    while (current) |c| {
        try path.append(allocator, c);
        current = prev[c];
    }

    std.mem.reverse(u32, path.items);

    return path.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    const road_file = "Road.txt";
    const place_file = "Place.txt";

    // Find max ID
    const max_id = try findMaxId(io, road_file);

    // Allocate graph
    const nodes = try allocator.alloc(Node, max_id + 1);

    for (nodes) |*n| {
        n.* = Node{
            .edges = .empty,
        };
    }

    var graph = Graph{ .nodes = nodes };

    // Build graph
    try buildGraph(allocator, io, road_file, &graph);

    // ID -> name
    const id_to_name = try allocator.alloc(?[]const u8, max_id + 1);
    for (id_to_name) |*n| n.* = null; // Initialize array

    try loadPlaceNames(allocator, io, place_file, id_to_name);

    // name -> ID
    var name_to_id = std.StringHashMap(std.ArrayList(u32)).init(allocator);
    try buildNameToIdMap(allocator, io, place_file, &name_to_id);

    if (name_to_id.get("MIKALAMAZOO N")) |list| {
        std.debug.print("Kalamazoo IDs: {any}\n", .{list.items});
    }
    if (name_to_id.get("MIANN ARBOR N")) |list| {
        std.debug.print("Ann Arbor IDs: {any}\n", .{list.items});
    }

    // Input
    var stdin_file = Io.File.stdin();
    var stdin_buf: [1024]u8 = undefined;
    var stdin = stdin_file.reader(io, &stdin_buf);
    const interface = &stdin.interface;

    std.debug.print("Enter the Source Name:\n", .{});
    const maybe_start_name = interface.takeDelimiter('\n') catch |err| return err;
    const start_name = try allocator.dupe(u8, std.mem.trim(u8, maybe_start_name.?, " \r\n\t"));

    std.debug.print("Enter the Destination Name:\n", .{});
    const maybe_end_name = interface.takeDelimiter('\n') catch |err| return err;
    const end_name = try allocator.dupe(u8, std.mem.trim(u8, maybe_end_name.?, " \r\n\t"));

    std.debug.print("START RAW: '{s}'\n", .{start_name});
    const start_list = name_to_id.get(start_name) orelse {
        std.debug.print("Start: {s} not found\n", .{start_name});
        return;
    };

    std.debug.print("TARGET RAW: '{s}'\n", .{end_name});
    const target_list = name_to_id.get(end_name) orelse {
        std.debug.print("Target: {s} not found\n", .{end_name});
        return;
    };

    // var it = name_to_id.iterator();
    // while (it.next()) |e| {
    //     std.debug.print("MAP KEY: '{s}'\n", .{e.key_ptr.*});
    // }

    const start = pickMinId(start_list);
    const target = pickMinId(target_list);

    std.debug.print(
        "Searching from {}({s}) to {}({s})\n", .{
            start,
            if (id_to_name[start]) |n| n else "null",
            target,
            if (id_to_name[target]) |n| n else "null",
        },
    );

    // Run Dijkstra
    const result = try dijkstra(allocator, &graph, start);

    std.debug.print("Distance: {}\n", .{result.dist[target]});

    // Path
    const path = try reconstructPath(allocator, result.prev, target);

    // Print path
    var total: f32 = 0;

    for (path, 0..) |node, i| {
        if (i == 0) continue;

        const prev = path[i - 1];

        // find edge weight
        for (graph.nodes[prev].edges.items) |edge| {
            if (edge.to == node) {
                total += edge.weight;

                std.debug.print(
                    "\t{}: {}({s}) -> {}({s}), {s}, {:.2} mi.\n",
                    .{
                        i,
                        prev,
                        if(id_to_name[prev]) |n| n else "null",
                        node,
                        if(id_to_name[node]) |n| n else "null",
                        edge.name,
                        edge.weight,
                    },
                );

                break;
            }
        }
    }

    std.debug.print(
        "\nIt takes {:.2} miles from {}({s}) to {}({s}).\n", .{
            total,
            start,
            if(id_to_name[start]) |n| n else "null",
            target,
            if(id_to_name[target]) |n| n else "null",
        },
    );
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!

    const gpa = std.testing.allocator;
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(gpa);
    while (!smith.eos()) switch (smith.value(enum { add_data, dup_data })) {
        .add_data => {
            const slice = try list.addManyAsSlice(gpa, smith.value(u4));
            smith.bytes(slice);
        },
        .dup_data => {
            if (list.items.len == 0) continue;
            if (list.items.len > std.math.maxInt(u32)) return error.SkipZigTest;
            const len = smith.valueRangeAtMost(u32, 1, @min(32, list.items.len));
            const off = smith.valueRangeAtMost(u32, 0, @intCast(list.items.len - len));
            try list.appendSlice(gpa, list.items[off..][0..len]);
            try std.testing.expectEqualSlices(
                u8,
                list.items[off..][0..len],
                list.items[list.items.len - len ..],
            );
        },
    };
}
