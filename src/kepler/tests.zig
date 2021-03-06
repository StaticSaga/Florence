const std = @import("std");
const os = @import("root").os;
const kepler = os.kepler;

const tries = 1_000_000;

fn server_task(allocator: *std.mem.Allocator, server_noteq: *kepler.ipc.NoteQueue) !void {
    // Server note queue should get the .Request note
    server_noteq.wait();
    const connect_note = server_noteq.try_recv() orelse unreachable;
    std.debug.assert(connect_note.typ == .RequestPending);
    const conn = connect_note.owner_ref.stream;
    os.log(".Request note recieved!\n", .{});

    // Accept the requests
    try connect_note.owner_ref.stream.accept();
    os.log("Request was accepted!\n", .{});

    // Test 10000000 requests
    var i: usize = 0;
    var server_send_rdtsc: u64 = 0;
    var server_recv_rdtsc: u64 = 0;
    os.log("Server task enters stress test!\n", .{});
    while (i < tries) : (i += 1) {
        // Server should get .Submit note
        server_noteq.wait();

        const recv_starting_time = os.platform.clock();
        const submit_note = server_noteq.try_recv() orelse unreachable;
        server_recv_rdtsc += os.platform.clock() - recv_starting_time;

        std.debug.assert(submit_note.typ == .TasksAvailable);
        std.debug.assert(submit_note.owner_ref.stream == conn);

        // Allow client to resent its note
        submit_note.drop();
        conn.unblock(.Consumer);

        // Notify consumer about completed tasks
        const send_starting_time = os.platform.clock();
        try conn.notify(.Consumer);
        server_send_rdtsc += os.platform.clock() - send_starting_time;
    }
    os.log("Server task exits stress test! Send: {} clk. Recieve: {} clk\n", .{ server_send_rdtsc / tries, server_recv_rdtsc / tries });

    // Terminate connection from the server
    conn.abandon(.Producer);
    os.log("Connection terminated from the server side!\n", .{});
}

fn client_task(allocator: *std.mem.Allocator, client_noteq: *kepler.ipc.NoteQueue, endpoint: *kepler.ipc.Endpoint) !void {
    // Stream connection object
    const conn_params = kepler.ipc.Stream.UserspaceInfo{
        .consumer_rw_buf_size = 1024,
        .producer_rw_buf_size = 1024,
        .obj_mailbox_size = 16,
    };
    const conn = try kepler.ipc.Stream.create(allocator, client_noteq, endpoint, conn_params);
    os.log("Created connection!\n", .{});

    // Client note queue should get the .Accept note
    client_noteq.wait();
    const accept_note = client_noteq.try_recv() orelse unreachable;
    std.debug.assert(accept_note.typ == .RequestAccepted);
    std.debug.assert(accept_note.owner_ref.stream == conn);
    accept_note.drop();
    os.log(".Accept note recieved!\n", .{});

    // Finalize accept/request sequence
    conn.finalize_connection();
    os.log("Connection finalized!\n", .{});

    // Test 10000000 requests
    var i: usize = 0;
    var client_send_rdtsc: usize = 0;
    var client_recv_rdtsc: usize = 0;
    os.log("Client task enters stress test!\n", .{});
    while (i < tries) : (i += 1) {
        // Let's notify server about more tasks
        const send_starting_time = os.platform.clock();
        try conn.notify(.Producer);
        client_send_rdtsc += os.platform.clock() - send_starting_time;

        // Client should get .Complete note
        client_noteq.wait();

        const recv_starting_time = os.platform.clock();
        const complete_note = client_noteq.try_recv() orelse unreachable;
        client_recv_rdtsc += os.platform.clock() - recv_starting_time;

        std.debug.assert(complete_note.typ == .ResultsAvailable);
        std.debug.assert(complete_note.owner_ref.stream == conn);
        complete_note.drop();

        // Allow server to resend its note
        conn.unblock(.Producer);
    }
    os.log("Client task exits stress test! Send: {} clk. Recieve: {} clk\n", .{ client_send_rdtsc / tries, client_recv_rdtsc / tries });

    // Client should get ping of death message
    client_noteq.wait();
    const server_death_note = client_noteq.try_recv() orelse unreachable;
    std.debug.assert(server_death_note.owner_ref.stream == conn);
    std.debug.assert(server_death_note.typ == .ProducerLeft);
    os.log("Ping of death recieved!\n", .{});
    server_death_note.drop();

    // Close connection on the client's side as well
    conn.abandon(.Consumer);
    os.log("Connection terminated from the client side!\n", .{});

    // Exit client task
    os.thread.scheduler.exit_task();
}

fn notifications(allocator: *std.mem.Allocator) !void {
    os.log("\nNotifications test...\n", .{});
    // Server notificaiton queue
    const server_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created server queue!\n", .{});
    // Client notification queue
    const client_noteq = try kepler.ipc.NoteQueue.create(allocator);
    os.log("Created client queue!\n", .{});
    // Server endpoint
    const endpoint = try kepler.ipc.Endpoint.create(allocator, server_noteq);
    os.log("Created server endpoint!\n", .{});

    // Run client task separately
    try os.thread.scheduler.spawn_task(client_task, .{ allocator, client_noteq, endpoint });

    // Launch server task inline
    try server_task(allocator, server_noteq);
    os.log("Server has terminated! Let's hope that client would finish as needed", .{});
}

fn memory_objects(allocator: *std.mem.Allocator) !void {
    os.log("\nMemory objects test...\n", .{});

    const test_obj = try kepler.memory.MemoryObject.create(allocator, 0x10000);
    os.log("Created memory object of size 0x10000!\n", .{});
    const base = try kepler.memory.kernel_mapper.map(test_obj, os.memory.paging.rw(), .MemoryWriteBack);
    os.log("Mapped memory object!\n", .{});
    const arr = @intToPtr([*]u8, base);
    arr[0] = 0x69;
    kepler.memory.kernel_mapper.unmap(test_obj, base);
    os.log("Unmapped memory object!\n", .{});

    const base2 = try kepler.memory.kernel_mapper.map(test_obj, os.memory.paging.ro(), .MemoryWriteBack);
    os.log("Mapped memory object again!\n", .{});
    const arr2 = @intToPtr([*]u8, base2);
    std.debug.assert(arr2[0] == 0x69);
    kepler.memory.kernel_mapper.unmap(test_obj, base2);
    os.log("Unmapped memory object again!\n", .{});

    test_obj.drop();
    os.log("Dropped memory object!\n", .{});
}

fn object_passing(allocator: *std.mem.Allocator) !void {
    os.log("\nObject passing test...\n", .{});

    var mailbox = try kepler.objects.ObjectRefMailbox.init(allocator, 2);
    os.log("Created object reference mailbox!\n", .{});

    // Create a dummy object to pass around
    const dummy = try kepler.memory.MemoryObject.create(allocator, 0x1000);
    os.log("Created dummy object!\n", .{});
    const dummy_ref = kepler.objects.ObjectRef{ .MemoryObject = .{ .ref = dummy.borrow(), .mapped_to = null } };

    // Test send from consumer and recieve from producer
    if (mailbox.write_from_consumer(3, dummy_ref)) {
        unreachable;
    } else |err| {
        std.debug.assert(err == error.OutOfBounds);
    }
    os.log("Out of bounds write passed!\n", .{});

    try mailbox.write_from_consumer(0, dummy_ref);
    os.log("Send passed!\n", .{});

    if (mailbox.write_from_consumer(0, dummy_ref)) {
        unreachable;
    } else |err| {
        std.debug.assert(err == error.NotEnoughPermissions);
    }
    os.log("Wrong send to the same cell passed!\n", .{});

    if (mailbox.read_from_producer(1)) |_| {
        unreachable;
    } else |err| {
        std.debug.assert(err == error.NotEnoughPermissions);
    }
    os.log("Read with wrong permissions passed!\n", .{});

    const recieved_dummy_ref = try mailbox.read_from_producer(0);
    std.debug.assert(recieved_dummy_ref.MemoryObject.ref == dummy_ref.MemoryObject.ref);
    recieved_dummy_ref.drop(&kepler.memory.kernel_mapper);
    os.log("Read passed!\n", .{});

    // Test grant from consumer, send from producer, and reciever from consumer
    try mailbox.grant_write(0);

    if (mailbox.write_from_producer(1, dummy_ref)) {
        unreachable;
    } else |err| {
        std.debug.assert(err == error.NotEnoughPermissions);
    }
    os.log("Write with wrong permissions passed!\n", .{});

    try mailbox.write_from_producer(0, dummy_ref);

    const new_recieved_dummy_ref = try mailbox.read_from_consumer(0);
    std.debug.assert(new_recieved_dummy_ref.MemoryObject.ref == dummy_ref.MemoryObject.ref);
    new_recieved_dummy_ref.drop(&kepler.memory.kernel_mapper);
    os.log("Read passed!\n", .{});

    dummy_ref.drop(&kepler.memory.kernel_mapper);
    mailbox.drop();
}

fn locked_handles(allocator: *std.mem.Allocator) !void {
    os.log("\nLocked handles test...\n", .{});
    const handle = try kepler.objects.LockedHandle.create(allocator, 69, 420);
    std.debug.assert((try handle.peek(420)) == 69);
    if (handle.peek(412)) |_| unreachable else |err| std.debug.assert(err == error.AuthenticationFailed);
    os.log("Locked handles test passed...\n", .{});
}

fn locked_handle_table(allocator: *std.mem.Allocator) !void {
    os.log("\nLocked handle table test...\n", .{});
    var instance: os.lib.handle_table.LockedHandleTable(u64) = .{};
    instance.init(allocator);

    const result1 = try instance.new_cell();
    result1.ref.* = 69;
    std.debug.assert(result1.id == 0);

    instance.unlock();
    os.log("First alloc done!...\n", .{});

    const result2 = try instance.new_cell();
    result2.ref.* = 420;
    std.debug.assert(result2.id == 1);

    instance.unlock();
    os.log("Second alloc done!...\n", .{});

    const TestDisposer = struct {
        called: u64,

        pub fn init() @This() {
            return .{ .called = 0 };
        }

        pub fn dispose(self: *@This(), loc: os.lib.handle_table.LockedHandleTable(u64).Location) void {
            self.called += 1;
        }
    };

    var disposer = TestDisposer.init();
    os.log("Disposing handle table...\n", .{});
    instance.deinit(TestDisposer, &disposer);
    std.testing.expect(disposer.called == 2);
}

fn interrupt_test(allocator: *std.mem.Allocator) !void {
    os.log("\nInterrupt test...\n", .{});
    // Create a notification queue
    const noteq = try kepler.ipc.NoteQueue.create(allocator);
    // Create interrupt object
    var object: kepler.interrupts.InterruptObject = undefined;
    const dummy_callback =  struct {fn dummy(_: *kepler.interrupts.InterruptObject) void {}}.dummy;
    object.init(noteq, dummy_callback, dummy_callback);
    // Raise interrupt
    object.raise();
    // Check that we got a notification
    const note = noteq.try_recv() orelse unreachable;
    std.debug.assert(note.typ == .InterruptRaised);
    note.drop();
    object.shutdown();
}

pub fn run_tests() !void {
    var buffer: [4096]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = &fixed_buffer.allocator;

    try notifications(allocator);
    try memory_objects(allocator);
    try object_passing(allocator);
    try locked_handles(allocator);
    try locked_handle_table(allocator);
    try interrupt_test(allocator);

    os.log("\nAll tests passing!\n", .{});
}
