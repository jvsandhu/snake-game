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
const TIMER_MS: i32 = 16;
const BASE_INTERVAL: i32 = 160;
const MIN_INTERVAL: i32 = 50;
const TIMER_ID: usize = 1;
const INPUT_BUF_SIZE = 2;

const Dir = enum { up, down, left, right };

const Pos = struct { x: i32, y: i32 };

fn isOpposite(a: Dir, b: Dir) bool {
    return switch (a) {
        .up => b == .down,
        .down => b == .up,
        .left => b == .right,
        .right => b == .left,
    };
}

const Game = struct {
    snake: std.ArrayList(Pos),
    dir: Dir,
    food: Pos,
    score: i32,
    high_score: i32,
    game_over: bool,
    death_reason: []const u8,
    death_flash: i32,
    paused: bool,
    wrap: bool,
    difficulty_ramp: bool,
    elapsed: i32,
    input_buf: [INPUT_BUF_SIZE]Dir,
    input_head: usize,
    input_count: usize,

    fn init(alloc: std.mem.Allocator, start_high_score: i32) Game {
        var body = std.ArrayList(Pos).init(alloc);
        const mx = COLS / 2;
        const my = ROWS / 2;
        body.append(.{ .x = mx, .y = my }) catch unreachable;
        body.append(.{ .x = mx - 1, .y = my }) catch unreachable;
        body.append(.{ .x = mx - 2, .y = my }) catch unreachable;
        return .{
            .snake = body,
            .dir = .right,
            .food = .{ .x = mx + 3, .y = my },
            .score = 0,
            .high_score = start_high_score,
            .game_over = false,
            .death_reason = "",
            .death_flash = 0,
            .paused = false,
            .wrap = false,
            .difficulty_ramp = false,
            .elapsed = 0,
            .input_buf = undefined,
            .input_head = 0,
            .input_count = 0,
        };
    }

    fn deinit(self: *Game) void {
        self.snake.deinit();
    }

    fn head(self: Game) Pos {
        return self.snake.items[0];
    }

    fn getMoveInterval(self: Game) i32 {
        if (!self.difficulty_ramp) return BASE_INTERVAL;
        return @max(MIN_INTERVAL, BASE_INTERVAL - self.score * 5);
    }

    fn pushDir(self: *Game, d: Dir) void {
        if (self.input_count >= INPUT_BUF_SIZE) return;
        const last = if (self.input_count > 0)
            self.input_buf[(self.input_head + self.input_count - 1) % INPUT_BUF_SIZE]
        else
            self.dir;
        if (isOpposite(last, d)) return;
        self.input_buf[(self.input_head + self.input_count) % INPUT_BUF_SIZE] = d;
        self.input_count += 1;
    }

    fn update(self: *Game) void {
        if (self.input_count > 0) {
            self.dir = self.input_buf[self.input_head];
            self.input_head = (self.input_head + 1) % INPUT_BUF_SIZE;
            self.input_count -= 1;
        }
        const h = self.head();
        var n = switch (self.dir) {
            .up => Pos{ .x = h.x, .y = h.y - 1 },
            .down => Pos{ .x = h.x, .y = h.y + 1 },
            .left => Pos{ .x = h.x - 1, .y = h.y },
            .right => Pos{ .x = h.x + 1, .y = h.y },
        };
        if (self.wrap) {
            if (n.x < 0) n.x = COLS - 1;
            if (n.x >= COLS) n.x = 0;
            if (n.y < 0) n.y = ROWS - 1;
            if (n.y >= ROWS) n.y = 0;
        } else {
            if (n.x < 0 or n.x >= COLS or n.y < 0 or n.y >= ROWS) {
                self.game_over = true;
                self.death_reason = "Hit a wall";
                self.death_flash = 200;
                if (self.score > self.high_score) {
                    self.high_score = self.score;
                    saveHighScore(self.high_score);
                }
                return;
            }
        }
        for (self.snake.items) |p| {
            if (p.x == n.x and p.y == n.y) {
                self.game_over = true;
                self.death_reason = "Ate yourself";
                self.death_flash = 200;
                if (self.score > self.high_score) {
                    self.high_score = self.score;
                    saveHighScore(self.high_score);
                }
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
        self.food = .{ .x = mx + 3, .y = my };
        self.score = 0;
        self.game_over = false;
        self.death_reason = "";
        self.death_flash = 0;
        self.paused = false;
        self.elapsed = 0;
        self.input_head = 0;
        self.input_count = 0;
    }
};

fn loadHighScore() i32 {
    const hfile = win.CreateFileA("snake.hs", win.GENERIC_READ, 0, null, win.OPEN_EXISTING, win.FILE_ATTRIBUTE_NORMAL, null);
    if (hfile == win.INVALID_HANDLE_VALUE) return 0;
    defer _ = win.CloseHandle(hfile);
    var buf: [16]u8 = std.mem.zeroes([16]u8);
    var read: win.DWORD = 0;
    if (win.ReadFile(hfile, &buf, buf.len, &read, null) == 0) return 0;
    const trimmed = std.mem.trimRight(u8, buf[0..read], &.{ 0, '\r', '\n', ' ' });
    return std.fmt.parseInt(i32, trimmed, 10) catch 0;
}

fn saveHighScore(score: i32) void {
    const hfile = win.CreateFileA("snake.hs", win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
    if (hfile == win.INVALID_HANDLE_VALUE) return;
    defer _ = win.CloseHandle(hfile);
    var buf: [16]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}\n", .{score}) catch return;
    var written: win.DWORD = 0;
    _ = win.WriteFile(hfile, text.ptr, @as(win.DWORD, @intCast(text.len)), &written, null);
}

fn wndProc(hwnd: win.HWND, msg: win.UINT, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.C) win.LRESULT {
    switch (msg) {
        win.WM_CREATE => {
            const create: *win.CREATESTRUCTA = @ptrFromInt(@as(usize, @intCast(lParam)));
            const game_ptr: *Game = @ptrCast(@alignCast(create.lpCreateParams.?));
            _ = win.SetWindowLongPtrA(hwnd, win.GWLP_USERDATA, @as(win.LONG_PTR, @intCast(@intFromPtr(game_ptr))));
            _ = win.SetTimer(hwnd, TIMER_ID, TIMER_MS, null);
            return 0;
        },
        win.WM_TIMER => {
            const game: *Game = @ptrFromInt(@as(usize, @intCast(win.GetWindowLongPtrA(hwnd, win.GWLP_USERDATA))));
            if (game.death_flash > 0) {
                game.death_flash -= TIMER_MS;
                if (game.death_flash < 0) game.death_flash = 0;
            }
            if (!game.game_over and !game.paused) {
                game.elapsed += TIMER_MS;
                const interval = game.getMoveInterval();
                while (game.elapsed >= interval) {
                    game.elapsed -= interval;
                    game.update();
                    if (game.game_over) break;
                }
            }
            _ = win.InvalidateRect(hwnd, null, win.TRUE);
            return 0;
        },
        win.WM_KEYDOWN => {
            const game: *Game = @ptrFromInt(@as(usize, @intCast(win.GetWindowLongPtrA(hwnd, win.GWLP_USERDATA))));
            switch (wParam) {
                'W', win.VK_UP => { if (game.dir != .down) game.pushDir(.up); },
                'S', win.VK_DOWN => { if (game.dir != .up) game.pushDir(.down); },
                'A', win.VK_LEFT => { if (game.dir != .right) game.pushDir(.left); },
                'D', win.VK_RIGHT => { if (game.dir != .left) game.pushDir(.right); },
                'R', 'r', win.VK_SPACE => {
                    if (game.game_over) {
                        game.reset();
                        _ = win.InvalidateRect(hwnd, null, win.TRUE);
                    }
                },
                'P', 'p' => {
                    if (!game.game_over) game.paused = !game.paused;
                },
                'O', 'o' => {
                    if (!game.game_over) game.wrap = !game.wrap;
                },
                'I', 'i' => {
                    if (!game.game_over) game.difficulty_ramp = !game.difficulty_ramp;
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

            var rc: win.RECT = undefined;
            _ = win.GetClientRect(hwnd, &rc);
            const cw = rc.right - rc.left;
            const ch = rc.bottom - rc.top;

            const mem_dc = win.CreateCompatibleDC(hdc);
            const bitmap = win.CreateCompatibleBitmap(hdc, cw, ch);
            const old_bmp = win.SelectObject(mem_dc, bitmap);
            defer {
                _ = win.SelectObject(mem_dc, old_bmp);
                _ = win.DeleteObject(bitmap);
                _ = win.DeleteDC(mem_dc);
            }

            drawGame(mem_dc, cw, ch, game);
            _ = win.BitBlt(hdc, 0, 0, cw, ch, mem_dc, 0, 0, win.SRCCOPY);
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

fn drawGame(hdc: win.HDC, cw: i32, ch: i32, game: *Game) void {
    const ox = @divFloor(cw - WIN_W, 2);
    const oy = @divFloor(ch - WIN_H, 2);

    const bg = win.CreateSolidBrush(0x00101010);
    defer _ = win.DeleteObject(bg);
    var full_rc = win.RECT{ .left = 0, .top = 0, .right = cw, .bottom = ch };
    _ = win.FillRect(hdc, &full_rc, bg);

    const grid_brush = win.CreateSolidBrush(0x00262626);
    defer _ = win.DeleteObject(grid_brush);

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

    // food
    r.left = ox + game.food.x * CELL;
    r.top = oy + HUD + game.food.y * CELL;
    r.right = r.left + CELL;
    r.bottom = r.top + CELL;
    const food_brush = win.CreateSolidBrush(0x000000AA);
    defer _ = win.DeleteObject(food_brush);
    _ = win.FillRect(hdc, &r, food_brush);

    // snake with tail gradient
    const len = game.snake.items.len;
    for (game.snake.items, 0..) |p, i| {
        const t = if (len > 1) @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(len - 1)) else 0;
        const g = @as(u32, @intFromFloat(220.0 - t * 160.0));
        const color = (g << 8);
        const seg_brush = win.CreateSolidBrush(@as(u32, @intCast(color)));
        defer _ = win.DeleteObject(seg_brush);
        r.left = ox + p.x * CELL;
        r.top = oy + HUD + p.y * CELL;
        r.right = r.left + CELL;
        r.bottom = r.top + CELL;
        _ = win.FillRect(hdc, &r, seg_brush);
    }

    // border
    const old_pen = win.SelectObject(hdc, win.GetStockObject(6));
    const old_brush = win.SelectObject(hdc, win.GetStockObject(5));
    _ = win.Rectangle(hdc, ox, oy + HUD, ox + WIN_W, oy + HUD + ROWS * CELL);
    _ = win.SelectObject(hdc, old_brush);
    _ = win.SelectObject(hdc, old_pen);

    // death flash
    if (game.death_flash > 0) {
        const flash_brush = win.CreateSolidBrush(0x000000AA);
        defer _ = win.DeleteObject(flash_brush);
        var flash_rc = win.RECT{ .left = ox, .top = oy + HUD, .right = ox + WIN_W, .bottom = oy + HUD + ROWS * CELL };
        _ = win.FillRect(hdc, &flash_rc, flash_brush);
    }

    // HUD
    _ = win.SetBkMode(hdc, win.TRANSPARENT);
    _ = win.SetTextColor(hdc, 0x00FFFFFF);

    var buf: [128]u8 = std.mem.zeroes([128]u8);
    var text: []const u8 = undefined;

    if (game.game_over) {
        text = std.fmt.bufPrint(&buf, "Score: {d}  Hi: {d}  ({s})", .{ game.score, game.high_score, game.death_reason }) catch buf[0..0];
    } else {
        text = std.fmt.bufPrint(&buf, "Score: {d}  Hi: {d}", .{ game.score, game.high_score }) catch buf[0..0];
    }
    _ = win.TextOutA(hdc, ox + 10, oy + 14, text.ptr, @as(i32, @intCast(text.len)));

    if (game.difficulty_ramp) {
        var speed_buf: [32]u8 = std.mem.zeroes([32]u8);
        const interval = game.getMoveInterval();
        const speed_text = std.fmt.bufPrint(&speed_buf, "Speed: {}ms", .{interval}) catch speed_buf[0..0];
        _ = win.SetTextColor(hdc, 0x00888888);
        _ = win.TextOutA(hdc, ox + 10, oy + 32, speed_text.ptr, @as(i32, @intCast(speed_text.len)));
        _ = win.SetTextColor(hdc, 0x00FFFFFF);
    }

    if (game.wrap or game.difficulty_ramp) {
        var mx = ox + WIN_W - 120;
        _ = win.SetTextColor(hdc, 0x00888888);
        if (game.wrap) {
            _ = win.TextOutA(hdc, mx, oy + 14, "WRAP", 4);
            mx += 48;
        }
        if (game.difficulty_ramp) {
            _ = win.TextOutA(hdc, mx, oy + 14, "RAMP", 4);
        }
        _ = win.SetTextColor(hdc, 0x00FFFFFF);
    }

    if (game.game_over) {
        const msg = "GAME OVER  -  R / SPACE to restart";
        var sz: win.SIZE = undefined;
        _ = win.GetTextExtentPoint32A(hdc, msg, @as(i32, @intCast(msg.len)), &sz);
        const x = @divFloor(cw - sz.cx, 2);
        const y = oy + HUD + @divFloor(ROWS * CELL, 2) - sz.cy;
        _ = win.SetTextColor(hdc, 0x000000AA);
        _ = win.TextOutA(hdc, x, y, msg, @as(i32, @intCast(msg.len)));
        _ = win.SetTextColor(hdc, 0x00FFFFFF);
    } else if (game.paused) {
        const msg = "PAUSED";
        var sz: win.SIZE = undefined;
        _ = win.GetTextExtentPoint32A(hdc, msg, @as(i32, @intCast(msg.len)), &sz);
        const x = @divFloor(cw - sz.cx, 2);
        const y = oy + HUD + @divFloor(ROWS * CELL, 2) - sz.cy;
        _ = win.SetTextColor(hdc, 0x00AAAAAA);
        _ = win.TextOutA(hdc, x, y, msg, @as(i32, @intCast(msg.len)));
        _ = win.SetTextColor(hdc, 0x00FFFFFF);
    }
}

pub fn main() !void {
    const hinst = win.GetModuleHandleA(null);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const high_score = loadHighScore();
    var game = Game.init(alloc, high_score);

    var wc = std.mem.zeroes(win.WNDCLASSA);
    wc.style = win.CS_HREDRAW | win.CS_VREDRAW;
    wc.lpfnWndProc = wndProc;
    wc.hInstance = hinst;
    wc.hIcon = null;
    wc.hCursor = null;
    wc.hbrBackground = null;
    wc.lpszClassName = "SnakeClass";

    if (win.RegisterClassA(&wc) == 0) return error.RegisterClassFailed;

    const fw = WIN_W + win.GetSystemMetrics(win.SM_CXFIXEDFRAME) * 2;
    const fh = WIN_H + win.GetSystemMetrics(win.SM_CYCAPTION) + win.GetSystemMetrics(win.SM_CYFIXEDFRAME) * 2;
    const sx = @divFloor(win.GetSystemMetrics(win.SM_CXSCREEN) - fw, 2);
    const sy = @divFloor(win.GetSystemMetrics(win.SM_CYSCREEN) - fh, 2);

    const hwnd = win.CreateWindowExA(
        0,
        "SnakeClass",
        "Snake",
        win.WS_OVERLAPPED | win.WS_CAPTION | win.WS_SYSMENU | win.WS_MINIMIZEBOX,
        sx,
        sy,
        fw,
        fh,
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
