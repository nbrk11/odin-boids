package main

import rl"vendor:raylib"
import "core:math"
import rand"core:math/rand"
import la"core:math/linalg"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
TARGET_FPS :: 60

BOID_NUMBER :: 2
BOID_WIDTH :: 10
BOID_HEIGHT :: 20
BOID_MAX_VELOCITY :: 20
BOID_MIN_VELOCITY :: 10

DEBUG_MODE :: true

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
}

draw_boid :: proc(boid: Boid) {
    rl.DrawTriangle(boid.pos + boid.vs[0], boid.pos + boid.vs[1], boid.pos + boid.vs[2], rl.MAROON) 
    // fmt.printf("[BOID_POS] X: %v Y: %v\n", boid.pos.x, boid.pos.y)
    // for v, i in boid.vs {
    //     fmt.printf("[BOID_VS] VS[%v] - X: %v Y: %v\n", i, v.x, v.y)
    // }
}

draw_debug_visuals :: proc(boid: Boid) {
    if DEBUG_MODE {
        rl.DrawCircleLinesV(boid.pos, boid.vision_range, rl.GREEN)
        rl.DrawCircleLinesV(boid.pos, boid.protected_range, rl.RED)
    }
}

vector_distance :: proc(v1, v2: rl.Vector2) -> f32 {
    return math.sqrt(math.pow2_f32(v2.x-v1.x) + math.pow2_f32(v2.y-v1.y))
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

apply_separation :: proc(b: ^Boid, boids: []Boid) {
    close_d := rl.Vector2{0,0}
    avoid_factor : f32 = 0.2 
    boids_copy := boids

    for nb in boids {
        if b^ == nb { continue; }
        if vector_distance(b.pos, nb.pos) > b.protected_range { continue; }

        close_d += (b.pos - nb.pos)
    }

    b.vel += close_d*avoid_factor 
}

update_boid_position :: proc(b: Boid, dt: f32) -> Boid {
    b := b
    b.pos += b.vel * dt

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

    b.vel = vector_clamp(b.vel, BOID_MIN_VELOCITY, BOID_MAX_VELOCITY)

    return b
}

get_angle_from_vector :: proc(v: rl.Vector2) -> f32 {
    return math.atan2(v.y, v.x) + math.PI/2
}

update_boid_rotation :: proc(boid: Boid, dt: f32) -> Boid {
    boid := boid
    angle := get_angle_from_vector(boid.vel)

    for &v, i in boid.base_vs {
        // this is basically the formula to rotate a triangle around the origin
        // the origin in this case is the "center" of the triangle
        xdt := v.x * math.cos(angle) - v.y * math.sin(angle)
        ydt := v.x * math.sin(angle) + v.y * math.cos(angle)
        rotationDt := rl.Vector2{ xdt, ydt }
        boid.vs[i] = rotationDt
    }

    return boid
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
    boid.protected_range = 40.0
    
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

        next := boids

        for i in 0..<BOID_NUMBER {
            b := boids[i]

            apply_separation(&b, boids[:])

            b = update_boid_position(b, dt)
            b = update_boid_rotation(b, dt)

            next[i] = b
        }

        boids = next

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
