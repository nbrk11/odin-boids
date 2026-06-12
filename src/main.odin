package main

import rl"vendor:raylib"
import "core:fmt"
import "core:math"
import rand"core:math/rand"
import la"core:math/linalg"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
TARGET_FPS :: 60

BOID_NUMBER :: 50
BOID_WIDTH :: 8
BOID_HEIGHT :: 15
BOID_MAX_VELOCITY :: 50
BOID_MIN_VELOCITY :: 30

AVOID_FACTOR : f32 : 0.02
MATCHING_FACTOR : f32 : 0.05

DEBUG_MODE :: false

Boid :: struct {
    vs: [3]rl.Vector2,
    // we need those to rotate around the local origin -> center of the triangle
    // otherwise we will be rotating around screen origin -> upper left corner of the screen
    base_vs: [3]rl.Vector2,
    using pos: rl.Vector2,
    vel: rl.Vector2,
    heading: f32,
    vision_range: f32,
    protected_range: f32,
    someone_in_protected_range: bool
}

draw_boid :: proc(boid: Boid) {
    rl.DrawTriangle(boid.pos + boid.vs[0], boid.pos + boid.vs[1], boid.pos + boid.vs[2], rl.MAROON) 
}

draw_debug_visuals :: proc(boid: Boid) {
    if DEBUG_MODE {
        if boid.someone_in_protected_range {
            rl.DrawCircleLinesV(boid.pos, boid.protected_range, rl.RED)
        } else {
            rl.DrawCircleLinesV(boid.pos, boid.protected_range, rl.BLUE)
        }
        rl.DrawCircleLinesV(boid.pos, boid.vision_range, rl.GREEN)
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

update_boids :: proc(boids: []Boid, dt: f32) {
    close_d, vel_avg : rl.Vector2
    neighboring_boids : i32

    for &b, i in boids {
        close_d = rl.Vector2{0,0}
        vel_avg = rl.Vector2{0,0}
        neighboring_boids = 0

        for nb, y in boids {
            if i == y { continue; }

            dv := b.pos - nb.pos

            if math.abs(dv.x) < b.vision_range && math.abs(dv.y) < b.vision_range {
                sqr_distance := la.vector_length2(dv)
                protected_range_squared := b.protected_range*b.protected_range
                vision_range_squared := b.vision_range*b.vision_range

                if sqr_distance < b.protected_range*b.protected_range {
                    b.someone_in_protected_range = true
                    close_d += dv
                } else {
                    vel_avg += nb.vel
                    neighboring_boids += 1
                    b.someone_in_protected_range = false
                }
            }
        }

        if neighboring_boids > 0 {
            vel_avg /= f32(neighboring_boids)
            b.vel += (vel_avg - b.vel)*MATCHING_FACTOR
        }

        b.vel += (close_d*AVOID_FACTOR)

        speed := la.vector_length(b.vel)

        if speed < BOID_MIN_VELOCITY {
            b.vel = (b.vel/speed)*BOID_MIN_VELOCITY
        }
        if speed > BOID_MAX_VELOCITY {
            b.vel = (b.vel/speed)*BOID_MAX_VELOCITY
        }

        b.pos += (b.vel * dt)

        if b.pos.x > SCREEN_WIDTH {
            b.pos.x = 0
        } else if b.pos.x < 0 {
            b.pos.x = SCREEN_WIDTH
        }

        if b.pos.y > SCREEN_HEIGHT{
            b.pos.y = 0
        } else if b.pos.y < 0 {
            b.pos.y = SCREEN_HEIGHT
        }

        // update rotation
        angle := get_angle_from_vector(b.vel)

        for &v, i in b.base_vs {
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
    boid.base_vs = [3]rl.Vector2{
        {   0, -BOID_HEIGHT/2 },            // top
        { -BOID_WIDTH/2,  BOID_HEIGHT/2 }, // bottom left
        {  BOID_WIDTH/2,  BOID_HEIGHT/2 }, // bottom right
    }
    boid.vision_range = 80.0
    boid.protected_range = 30.0
    
    return
}

main :: proc() {
    velocity ::  rl.Vector2{ 0, 0 }
    dt : f32 = 0.0
    dt = rl.GetFrameTime()

    boids := [BOID_NUMBER]Boid{}
    for &b, i in boids {
        b = create_boid_at_random_position()
    }

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Window")

    rl.SetTargetFPS(TARGET_FPS)
    boids_slice := boids[:]

    for !rl.WindowShouldClose() {
        dt = rl.GetFrameTime()

        update_boids(boids[:], dt)

        rl.BeginDrawing()

        rl.ClearBackground(rl.RAYWHITE)

        for b in boids {
            draw_boid(b)
            draw_debug_visuals(b)
        }

        rl.EndDrawing()
    }
    
    rl.CloseWindow()
}
