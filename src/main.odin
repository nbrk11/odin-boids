package main

import rl"vendor:raylib"
import "core:math"
import rand"core:math/rand"
import la"core:math/linalg"
import "core:fmt"
import "core:strings"
import th"core:thread"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
MARGIN_WIDTH :: 100
MARGIN_HEIGHT :: 100
TARGET_FPS :: 60

BOID_COUNT :: 800
BOID_WIDTH :: 7
BOID_HEIGHT :: 12
BOID_MAX_VELOCITY :: 180
BOID_MIN_VELOCITY :: 90

TURN_FACTOR : f32 : 6
VISION_RANGE : f32 : 70.0
PROTECTED_RANGE : f32 : 15.0
CENTERING_FACTOR : f32 : 0.0005
AVOID_FACTOR : f32 : 0.05
MATCHING_FACTOR : f32 : 0.05
MAX_BIAS : f32 : 0.01
BIAS_INC : f32 : 0.00004
BIAS_VAL : f32 : 0.001

THREAD_COUNT :: 8
THREAD_CHUNK_SIZE :: BOID_COUNT / THREAD_COUNT

DEBUG_MODE :: false

BASE_VS :: [3]rl.Vector2{
    {   0, -BOID_HEIGHT/2 },            // top
    { -BOID_WIDTH/2,  BOID_HEIGHT/2 }, // bottom left
    {  BOID_WIDTH/2,  BOID_HEIGHT/2 }, // bottom right
}

ScoutGroup :: enum {
    Right, Left
}

Boid :: struct {
    using pos: rl.Vector2,
    vel: rl.Vector2,
    vs: [3]rl.Vector2,
    bias_val: f32,
    bias: ScoutGroup,
}

WorkerData :: struct {
    boids: #soa[]Boid,
    chunk: u16,
    dt: f32
}

draw_boid :: proc(boid: Boid) {
    rl.DrawTriangle(boid.pos + boid.vs[0], boid.pos + boid.vs[1], boid.pos + boid.vs[2], rl.MAROON) 
}

draw_debug_visuals :: proc(boid: Boid) {
    if DEBUG_MODE {
        rl.DrawCircleLinesV(boid.pos, PROTECTED_RANGE, rl.RED)
        rl.DrawCircleLinesV(boid.pos, VISION_RANGE, rl.GREEN)
    }
}

vector_distance :: proc(v1, v2: rl.Vector2) -> f32 {
    return la.vector_length(v1 - v2)
}

vector_random :: proc() -> rl.Vector2 {
    return rl.Vector2{rand.float32(), rand.float32()}
}

vector_random_range :: proc(min, max: f32) -> rl.Vector2 {
    return rl.Vector2{rand.float32_range(min, max), rand.float32_range(min, max)}
}

vector_random_unit :: proc() -> rl.Vector2 {
    for {
        v := vector_random_range(-1.0, 1.0)
        lensq := la.vector_length(v) * la.vector_length(v)
        if 1e-160 < lensq && lensq <= 1 {
            return v / math.sqrt(lensq)
        }
    }
}

vector_clamp :: proc(v: rl.Vector2, min, max: f32) -> rl.Vector2 {
    v := v
    length := la.vector_length(v)

    if length > max {
        return (v / length) * max 
    }

    if length < min {
        return (v / length) * min
    }

    return v
}

update_boids_async :: proc(data: rawptr) {
    w := (^WorkerData)(data)
    boids := w.boids


    close_d, vel_avg, pos_avg : rl.Vector2
    neighboring_boids : i32

    if boids[0] == {} { return }

    for i := w.chunk*THREAD_CHUNK_SIZE; i < w.chunk*THREAD_CHUNK_SIZE + THREAD_CHUNK_SIZE; i += 1 {
        b := boids[i]
        close_d = rl.Vector2{0,0}
        vel_avg = rl.Vector2{0,0}
        pos_avg = rl.Vector2{0,0}
        neighboring_boids = 0

        for nb, y in boids {
            if int(i) == y { continue; }

            dv := b.pos - nb.pos

            if math.abs(dv.x) < VISION_RANGE && math.abs(dv.y) < VISION_RANGE {
                sqr_distance := la.vector_length2(dv)
                protected_range_squared := PROTECTED_RANGE*PROTECTED_RANGE

                if sqr_distance < protected_range_squared {
                    close_d += dv
                } else {
                    vel_avg += nb.vel
                    pos_avg += nb.pos
                    neighboring_boids += 1
                }
            }
        }

        if neighboring_boids > 0 {
            vel_avg /= f32(neighboring_boids)
            pos_avg /= f32(neighboring_boids)
            b.vel += (vel_avg - b.vel)*MATCHING_FACTOR
            b.vel += (pos_avg - b.pos)*CENTERING_FACTOR
        }

        b.vel += (close_d*AVOID_FACTOR)

        if b.pos.x > SCREEN_WIDTH - MARGIN_WIDTH {
            b.vel.x -= TURN_FACTOR
        }
        if b.pos.x < MARGIN_WIDTH {
            b.vel.x += TURN_FACTOR
        }
        if b.pos.y > SCREEN_HEIGHT - MARGIN_HEIGHT {
            b.vel.y -= TURN_FACTOR 
        }
        if b.pos.y < MARGIN_HEIGHT {
            b.vel.y += TURN_FACTOR
        }

        // bias
        if b.bias == ScoutGroup.Right {
            if b.vel.x > 0 {
                b.bias_val = math.min(MAX_BIAS, b.bias_val + BIAS_INC)
            } else {
                b.bias_val = math.max(BIAS_INC, b.bias_val - BIAS_INC)
            }
        } else if b.bias == ScoutGroup.Left {
            if b.vel.x < 0 {
                b.bias_val = math.min(MAX_BIAS, b.bias_val + BIAS_INC)
            } else {
                b.bias_val = math.max(BIAS_INC, b.bias_val - BIAS_INC)
            }
        }

        if b.bias == ScoutGroup.Right {
            b.vel.x = (1 - b.bias_val)*b.vel.x + (b.bias_val * 1)
        } else if b.bias == ScoutGroup.Left {
            b.vel.x = (1 - b.bias_val)*b.vel.x + (b.bias_val * (-1))
        }

        // update position
        b.vel = vector_clamp(b.vel, BOID_MIN_VELOCITY, BOID_MAX_VELOCITY)
        b.pos += (b.vel * w.dt)

        // update rotation
        angle := get_angle_from_vector(b.vel)

        for v, i in BASE_VS {
            // this is basically the formula to rotate a triangle around the origin
            // the origin in this case is the "center" of the triangle
            xdt := v.x * math.cos(angle) - v.y * math.sin(angle)
            ydt := v.x * math.sin(angle) + v.y * math.cos(angle)
            rotationDt := rl.Vector2{ xdt, ydt }
            b.vs[i] = rotationDt
        }

        boids[i].vel = b.vel
        boids[i].pos = b.pos
        boids[i].vs  = b.vs
    }
}

update_boids :: proc(boids: #soa[]Boid, dt: f32) {
    close_d, vel_avg, pos_avg : rl.Vector2
    neighboring_boids : i32

    if boids[0] == {} { return }

    for &b, i in boids {
        close_d = rl.Vector2{0,0}
        vel_avg = rl.Vector2{0,0}
        pos_avg = rl.Vector2{0,0}
        neighboring_boids = 0

        for nb, y in boids {
            if i == y { continue; }

            dv := b.pos - nb.pos

            if math.abs(dv.x) < VISION_RANGE && math.abs(dv.y) < VISION_RANGE {
                sqr_distance := la.vector_length2(dv)
                protected_range_squared := PROTECTED_RANGE*PROTECTED_RANGE

                if sqr_distance < protected_range_squared {
                    close_d += dv
                } else {
                    vel_avg += nb.vel
                    pos_avg += nb.pos
                    neighboring_boids += 1
                }
            }
        }

        if neighboring_boids > 0 {
            vel_avg /= f32(neighboring_boids)
            pos_avg /= f32(neighboring_boids)
            b.vel += (vel_avg - b.vel)*MATCHING_FACTOR
            b.vel += (pos_avg - b.pos)*CENTERING_FACTOR
        }

        b.vel += (close_d*AVOID_FACTOR)

        if b.pos.x > SCREEN_WIDTH - MARGIN_WIDTH {
            b.vel.x -= TURN_FACTOR
        }
        if b.pos.x < MARGIN_WIDTH {
            b.vel.x += TURN_FACTOR
        }
        if b.pos.y > SCREEN_HEIGHT - MARGIN_HEIGHT {
            b.vel.y -= TURN_FACTOR 
        }
        if b.pos.y < MARGIN_HEIGHT {
            b.vel.y += TURN_FACTOR
        }

        // bias
        if b.bias == ScoutGroup.Right {
            if b.vel.x > 0 {
                b.bias_val = math.min(MAX_BIAS, b.bias_val + BIAS_INC)
            } else {
                b.bias_val = math.max(BIAS_INC, b.bias_val - BIAS_INC)
            }
        } else if b.bias == ScoutGroup.Left {
            if b.vel.x < 0 {
                b.bias_val = math.min(MAX_BIAS, b.bias_val + BIAS_INC)
            } else {
                b.bias_val = math.max(BIAS_INC, b.bias_val - BIAS_INC)
            }
        }

        if b.bias == ScoutGroup.Right {
            b.vel.x = (1 - b.bias_val)*b.vel.x + (b.bias_val * 1)
        } else if b.bias == ScoutGroup.Left {
            b.vel.x = (1 - b.bias_val)*b.vel.x + (b.bias_val * (-1))
        }

        // update position
        b.vel = vector_clamp(b.vel, BOID_MIN_VELOCITY, BOID_MAX_VELOCITY)
        b.pos += (b.vel * dt)

        // update rotation
        angle := get_angle_from_vector(b.vel)

        for v, i in BASE_VS {
            // this is basically the formula to rotate a triangle around the origin
            // the origin in this case is the "center" of the triangle
            xdt := v.x * math.cos(angle) - v.y * math.sin(angle)
            ydt := v.x * math.sin(angle) + v.y * math.cos(angle)
            rotationDt := rl.Vector2{ xdt, ydt }
            b.vs[i] = rotationDt
        }
    }
}

get_angle_from_vector :: proc(v: rl.Vector2) -> f32 {
    return math.atan2(v.y, v.x) + math.PI/2
}

create_boid_at_random_position :: proc() -> (boid: Boid) {  
    boundaries :: [2]rl.Vector2{
        { 60, 80 },
        { SCREEN_WIDTH - 60, SCREEN_HEIGHT - 80 },
    }
    random_pos := rl.Vector2{ rand.float32_range(boundaries[0].x, boundaries[1].x), rand.float32_range(boundaries[0].y, boundaries[1].y) }

    boid.pos = random_pos    
    boid.vel = vector_clamp(vector_random_unit(), BOID_MIN_VELOCITY, BOID_MAX_VELOCITY)
    boid.vs = [3]rl.Vector2{
        {   0, -BOID_HEIGHT/2},            // top
        { -BOID_WIDTH/2,  BOID_HEIGHT/2}, // bottom left
        {  BOID_WIDTH/2,  BOID_HEIGHT/2}, // bottom right
    }

    if rand.float32() > 0.5 {
        boid.bias = ScoutGroup.Right
    } else {
        boid.bias = ScoutGroup.Left
    }
    boid.bias_val = BIAS_VAL

    return
}

main :: proc() {
    dt : f32 = 0.0
    boids : #soa[BOID_COUNT]Boid
    threads := [THREAD_COUNT]^th.Thread{}

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Boids")
    rl.SetTargetFPS(TARGET_FPS)
    defer rl.CloseWindow()

    w_data : [THREAD_COUNT]WorkerData

    for !rl.WindowShouldClose() {
        if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
            for &b, i in boids {
                b = create_boid_at_random_position()
            }
        }

        dt = rl.GetFrameTime()

        for t in threads {
            if t != nil { th.destroy(t) }
        }
        
        for &t, i in threads {
            w_data[i] = { boids = boids[:], chunk = u16(i), dt = dt } 
            t = th.create_and_start_with_data(&w_data[i], update_boids_async)
        }

        for t in threads {
            th.join(t)
        }
        // update_boids(boids[:], dt)

        rl.BeginDrawing()
        rl.DrawFPS(15, 15)
        boid_count_str := fmt.tprintf("Boid count: {0}", len(boids))
        cstr := strings.clone_to_cstring(boid_count_str, context.temp_allocator)
        rl.DrawText(cstr, 15, 40, 20, rl.LIGHTGRAY)

        rl.ClearBackground(rl.RAYWHITE)

        for b in boids {
            draw_boid(b)
            draw_debug_visuals(b)
        }

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }
}
