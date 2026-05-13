const std = @import("std");
const win = @cImport({
    @cDefine("WIN32_LEAN_AND_MEAN", "");
    @cDefine("NOMINMAX", "");
    @cInclude("windef.h");
    @cInclude("winbase.h");
    @cInclude("wingdi.h");
    @cInclude("winuser.h");
});

const COLS: i32 = 20;
const ROWS: i32 = 20;
const CELL: i32 = 28;
const HUD: i32 = 56;
const WIN_W: i32 = COLS * CELL;
const WIN_H: i32 = ROWS * CELL + HUD;
const TICK_MS: i32 = 160;
const TIMER_ID: usize = 1;

const Dir = enum { up, down, left, right };

const Pos = struct { x: i32, y: i32 };

const Game = struct {
    snake: std.ArrayList(Pos),
    dir: Dir,
    next_dir: Dir,
    food: Pos,
    score: i32,
    game_over: bool,

    fn init(alloc: std.mem.Allocator) Game {
        var body = std.ArrayList(Pos).init(alloc);
        const mx = COLS / 2;
        const my = ROWS / 2;
        body.append(.{ .x = mx, .y = my }) catch unreachable;
        body.append(.{ .x = mx - 1, .y = my }) catch unreachable;
        body.append(.{ .x = mx - 2, .y = my }) catch unreachable;
        return .{
            .snake = body,
            .dir = .right,
            .next_dir = .right,
            .food = .{ .x = mx + 3, .y = my },
            .score = 0,
            .game_over = false,
        };
    }

    fn deinit(self: *Game) void {
        self.snake.deinit();
    }

    fn head(self: Game) Pos {
        return self.snake.items[0];
    }

    fn update(self: *Game) void {
        self.dir = self.next_dir;
        const h = self.head();
        const n = switch (self.dir) {
            .up => Pos{ .x = h.x, .y = h.y - 1 },
            .down => Pos{ .x = h.x, .y = h.y + 1 },
            .left => Pos{ .x = h.x - 1, .y = h.y },
            .right => Pos{ .x = h.x + 1, .y = h.y },
        };
        if (n.x < 0 or n.x >= COLS or n.y < 0 or n.y >= ROWS) {
            self.game_over = true;
            return;
        }
        for (self.snake.items) |p| {
            if (p.x == n.x and p.y == n.y) {
                self.game_over = true;
                return;
            }
        }
        var grew = false;
        if (n.x == self.food.x and n.y == self.food.y) {
            grew = true;
            self.score += 1;
        }
        self.snake.insert(0, n) catch unreachable;
        if (!grew) _ = self.snake.pop();
        if (grew) self.spawnFood();
    }

    fn spawnFood(self: *Game) void {
        const seed: u64 = @truncate(@as(u128, @bitCast(std.time.nanoTimestamp())));
        var prng = std.Random.DefaultPrng.init(seed);
        const rand = prng.random();
        while (true) {
            const p = Pos{ .x = rand.intRangeAtMost(i32, 0, COLS - 1), .y = rand.intRangeAtMost(i32, 0, ROWS - 1) };
            var ok = true;
            for (self.snake.items) |s| {
                if (s.x == p.x and s.y == p.y) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                self.food = p;
                return;
            }
        }
    }

    fn reset(self: *Game) void {
        self.snake.deinit();
        const mx = COLS / 2;
        const my = ROWS / 2;
        var body = std.ArrayList(Pos).init(self.snake.allocator);
        body.append(.{ .x = mx, .y = my }) catch unreachable;
        body.append(.{ .x = mx - 1, .y = my }) catch unreachable;
        body.append(.{ .x = mx - 2, .y = my }) catch unreachable;
        self.snake = body;
        self.dir = .right;
        self.next_dir = .right;
        self.food = .{ .x = mx + 3, .y = my };
        self.score = 0;
        self.game_over = false;
    }
};

fn wndProc(hwnd: win.HWND, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.C) win.LRESULT {
    switch (msg) {
        win.WM_CREATE => {
            const create: *win.CREATESTRUCTA = @ptrFromInt(@as(usize, @intCast(lParam)));
            const game_ptr: *Game = @ptrCast(@alignCast(create.lpCreateParams.?));
            _ = win.SetWindowLongPtrA(hwnd, win.GWLP_USERDATA, @as(win.LONG_PTR, @intCast(@intFromPtr(game_ptr))));
            _ = win.SetTimer(hwnd, TIMER_ID, TICK_MS, null);
            return 0;
        },
        win.WM_TIMER => {
            const game: *Game = @ptrFromInt(@as(usize, @intCast(win.GetWindowLongPtrA(hwnd, win.GWLP_USERDATA))));
            if (!game.game_over) game.update();
            _ = win.InvalidateRect(hwnd, null, win.TRUE);
            return 0;
        },
        win.WM_KEYDOWN => {
            const game: *Game = @ptrFromInt(@as(usize, @intCast(win.GetWindowLongPtrA(hwnd, win.GWLP_USERDATA))));
            switch (wParam) {
                win.VK_UP => { if (game.dir != .down) game.next_dir = .up; },
                win.VK_DOWN => { if (game.dir != .up) game.next_dir = .down; },
                win.VK_LEFT => { if (game.dir != .right) game.next_dir = .left; },
                win.VK_RIGHT => { if (game.dir != .left) game.next_dir = .right; },
                'R', 'r', win.VK_SPACE => {
                    if (game.game_over) {
                        game.reset();
                        _ = win.InvalidateRect(hwnd, null, win.TRUE);
                    }
                },
                else => {},
            }
            return 0;
        },
        win.WM_PAINT => {
            var ps: win.PAINTSTRUCT = undefined;
            const hdc = win.BeginPaint(hwnd, &ps);
            defer _ = win.EndPaint(hwnd, &ps);
            const game: *Game = @ptrFromInt(@as(usize, @intCast(win.GetWindowLongPtrA(hwnd, win.GWLP_USERDATA))));
            drawGame(hwnd, hdc, game);
            return 0;
        },
        win.WM_DESTROY => {
            _ = win.KillTimer(hwnd, TIMER_ID);
            win.PostQuitMessage(0);
            return 0;
        },
        else => return win.DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

fn drawGame(hwnd: win.HWND, hdc: win.HDC, game: *Game) void {
    var rc: win.RECT = undefined;
    _ = win.GetClientRect(hwnd, &rc);

    const width = rc.right - rc.left;
    const height = rc.bottom - rc.top;
    const ox = @divFloor(width - WIN_W, 2);
    const oy = @divFloor(height - WIN_H, 2);

    const bg = win.CreateSolidBrush(0x00101010);
    defer _ = win.DeleteObject(bg);
    _ = win.FillRect(hdc, &rc, bg);

    const grid_brush = win.CreateSolidBrush(0x00262626);
    defer _ = win.DeleteObject(grid_brush);

    const snake_brush = win.CreateSolidBrush(0x0000AA00);
    defer _ = win.DeleteObject(snake_brush);

    const head_brush = win.CreateSolidBrush(0x0000DD00);
    defer _ = win.DeleteObject(head_brush);

    const food_brush = win.CreateSolidBrush(0x000000AA);
    defer _ = win.DeleteObject(food_brush);

    var r: win.RECT = undefined;

    for (0..@as(usize, @intCast(ROWS))) |ry| {
        for (0..@as(usize, @intCast(COLS))) |rx| {
            r.left = ox + @as(i32, @intCast(rx)) * CELL;
            r.top = oy + HUD + @as(i32, @intCast(ry)) * CELL;
            r.right = r.left + CELL - 1;
            r.bottom = r.top + CELL - 1;
            _ = win.FillRect(hdc, &r, grid_brush);
        }
    }

    r.left = ox + game.food.x * CELL;
    r.top = oy + HUD + game.food.y * CELL;
    r.right = r.left + CELL;
    r.bottom = r.top + CELL;
    _ = win.FillRect(hdc, &r, food_brush);

    for (game.snake.items, 0..) |p, i| {
        const brush = if (i == 0) head_brush else snake_brush;
        r.left = ox + p.x * CELL;
        r.top = oy + HUD + p.y * CELL;
        r.right = r.left + CELL;
        r.bottom = r.top + CELL;
        _ = win.FillRect(hdc, &r, brush);
    }

    var buf: [64]u8 = std.mem.zeroes([64]u8);
    const text = std.fmt.bufPrint(&buf, "Score: {d}", .{game.score}) catch buf[0..0];
    _ = win.SetBkMode(hdc, win.TRANSPARENT);
    _ = win.SetTextColor(hdc, 0x00FFFFFF);
    _ = win.TextOutA(hdc, ox + 10, oy + 14, text.ptr, @as(i32, @intCast(text.len)));

    if (game.game_over) {
        const msg = "GAME OVER - press R or SPACE to restart";
        var sz: win.SIZE = undefined;
        _ = win.GetTextExtentPoint32A(hdc, msg, @as(i32, @intCast(msg.len)), &sz);
        const x = @divFloor(width - sz.cx, 2);
        const y = @divFloor(height - sz.cy, 2);
        _ = win.SetTextColor(hdc, 0x000000AA);
        _ = win.TextOutA(hdc, x, y, msg, @as(i32, @intCast(msg.len)));
    }
}

pub fn main() !void {
    const hinst = win.GetModuleHandleA(null);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    var game = Game.init(alloc);

    var wc = std.mem.zeroes(win.WNDCLASSA);
    wc.style = win.CS_HREDRAW | win.CS_VREDRAW;
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hinst;
    wc.hIcon = null;
    wc.hCursor = null;
    wc.hbrBackground = null;
    wc.lpszClassName = "SnakeClass";

    if (win.RegisterClassA(&wc) == 0) return error.RegisterClassFailed;

    const hwnd = win.CreateWindowExA(
        0,
        "SnakeClass",
        "Snake",
        win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU | win.WS_MINIMIZEBOX,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        WIN_W + win.GetSystemMetrics(win.SM_CXFIXEDFRAME) * 2,
        WIN_H + win.GetSystemMetrics(win.SM_CYCAPTION) + win.GetSystemMetrics(win.SM_CYFIXEDFRAME) * 2,
        null,
        null,
        hinst,
        &game,
    );

    if (hwnd == null) return error.CreateWindowFailed;

    _ = win.ShowWindow(hwnd, win.SW_SHOWDEFAULT);
    _ = win.UpdateWindow(hwnd);

    var msg: win.MSG = undefined;
    while (win.GetMessageA(&msg, null, 0, 0) > 0) {
        _ = win.TranslateMessage(&msg);
        _ = win.DispatchMessageA(&msg);
    }

    game.deinit();
}
