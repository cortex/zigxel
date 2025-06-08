pub const RGB3 = packed struct {
    r: u1,
    g: u1,
    b: u1,
};

pub const RGB2x3 = packed struct {
    p1: RGB3,
    p2: RGB3,
};
