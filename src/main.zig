const std = @import("std");
const Io = std.Io;

const Assignment_4 = @import("Assignment_4");

const Edge = struct {
    to: u32,
    weight: u32
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

fn lessThan(_: void, a: PQItem, b: PQItem) bool {
    return a.dist < b.dist; // for min-heap
}

//-----------------------------
// Name -> ID Helper
//-----------------------------
fn getOrCreateId(
    name_map: *std.AutoHashMap([]const u8, u32),
    allocator: std.mem.Allocator,
    name: []const u8,
    next_id: *u32,
) !u32 {
    if (name_map.get(name)) |id| {
        return id;
    }

    const owned = try allocator.dupe(u8, name);

    const id = next_id.*;
    next_id.* += 1;

    try name_map.put(owned, id);
    return id;
}

//-----------------------------
// First pass: count + map IDS
//-----------------------------
fn firstPass(
    allocator: std.mem.Allocator,
    filename: []const u8,
    name_map: *std.AutoHashMap([]const u8, u32),
) !u32 {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var reader = file.reader();
    var buf: [1028]u8 = undefined;

    var next_id: u32 = 0;

    while(try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if(line.len == 0) continue;

        var it = std.mem.splitScalar(u8, line, ',');

        const from = it.next() orelse continue;
        const to = it.next() orelse continue;

        _ = try getOrCreateId(name_map, allocator, from, &next_id);
        _ = try getOrCreateId(name_map, allocator, to, &next_id);
    }

    return next_id;
}

//-----------------------------
// Second pass: build graph
//-----------------------------
fn secondPass(
    allocator: std.mem.Allocator,
    filename: []const u8,
    name_map: *std.AutoHashMap([]const u8, u32),
    graph: *Graph,
) !void {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var reader = file.reader();
    var buf: [1028]u8 = undefined;

    while(try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        if(line.len == 0) continue;

        var it = std.mem.splitScalar(u8, line, ',');

        const from_name = it.next() orelse continue;
        const to_name = it.next() orelse continue;
        const weight_str = it.next() orelse continue;

        const weight = try std.fmt.parseFloat(f32, weight_str);

        const from_id = name_map.get(from_name).?;
        const to_id = name_map.get(to_name).?;

        try graph.nodes[from_id].edges.append(.{
            .to = to_id,
            .weight = weight,
        });

        // If undirected, also add reverse
        try graph.nodes[to_id].edges.append(.{
            .to = from_id,
            .weight = weight,
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
    prev: []?f32,
} {
    const n = graph.nodes.len;

    var dist = try allocator.alloc(f32, n);
    var prev = try allocator.alloc(?u32, n);

    for(dist) |*d| d.* = std.math.inf(f32);
    for(prev) |*p| p.* = null;

    dist[start] = 0;

    var pq = std.PriorityQueue(PQItem, void, lessThan).init(allocator, {});
    try pq.add(.{ .node = start, .dist = 0 });

    while(pq.removeOrNull()) |item| {
        const u = item.node;

        if(item.dist > dist[u]) continue;

        for(graph.nodes[u].edges.items) |edge| {
            const alt = dist[u] + edge.weight;

            if(alt < dist[edge.to]) {
                dist[edge.to] = alt;
                prev[edge.to] = u;

                try pq.add(.{
                    .node = edge.to,
                    .dist = alt,
                });
            }
        }
    }

    return .{ .dist = dist, .prev = prev };
}

//-----------------------------
// Path Reconstruction
//-----------------------------
fn reconstructPath(
    allocator: std.mem.Allocator,
    prev: []?u32,
    target: u32,
) ![]u32 {
    var path = std.ArrayList(u32).init(allocator);

    var current: ?u32 = target;

    while(current) |c| {
        try path.append(c);
        current = prev[c];
    }

    std.mem.reverse(u32, path.items);

    return path.toOwnedSlice();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    // TODO: Change this to the ACTUAL filename
    const filename = "graph.csv";

    var name_map = std.AutoHashMap([]const u8, u32).init(allocator);

    // First pass
    const num_nodes = try firstPass(allocator, filename, &name_map);

    std.debug.print("Nodes: {}\n", .{num_nodes});

    // Allocate graph
    var nodes = try allocator.alloc(Node, num_nodes);

    for(nodes) |*n| {
        n.* = Node{
            .edges = std.ArrayList(Edge).init(allocator),
        };
    }

    var graph = Graph{ .nodes = nodes };

    // Second pass
    try secondPass(allocator, filename, &name_map, &graph);

    // Reverse map
    var id_to_name = try allocator.alloc([]const u8, num_nodes);

    var it = name_map.iterator();
    while(it.next()) |entry| {
        id_to_name[entry.value_ptr.*] = entry.key_ptr.*;
    }

    // Example query
    const start_name = "A";
    const end_name = "B";

    const start = name_map.get(start_name) orelse {
        std.debug.print("Start not found\n", .{});
        return;
    };

    const target = name_map.get(end_name) orelse {
        std.debug.print("Target not found\n", .{});
        return;
    };

    // Run Dijkstra
    const result = try dijkstra(allocator, &graph, start);

    std.debug.print("Distance: {}\n", .{ result.dist[target] });

    // Path
    const path = try reconstructPath(allocator, result.prev, target);

    std.debug.print("Path:\n", .{});
    for(path) |id| {
        std.debug.print("{s}\n", .{id_to_name[id]});
    }
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
