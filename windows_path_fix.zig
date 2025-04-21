const std = @import("std");
const builtin = @import("builtin");

pub export fn burrito_plugin_entry() void {
    // Only apply fixes on Windows
    if (builtin.os.tag != .windows) {
        return;
    }

    // Log that we're fixing Windows paths
    std.debug.print("Applying Windows path fixes for Burrito...\n", .{});

    // We don't need to do anything else as this is just a hook point
    // The real fix happens in the mix.exs configuration
} 