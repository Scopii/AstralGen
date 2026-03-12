const std = @import("std");

pub const TimeState = struct {
    // Set and used
    startup: i128 = 0,
    lastTime: i128 = 0,

    // Calculated Repeatedly
    runtime: i128 = 0,
    deltaTime: i128 = 0,
};
