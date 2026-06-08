package main

import rl"vendor:raylib"
import "core:math"
import "core:fmt"
import rand"core:math/rand"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600
TARGET_FPS :: 60

BOID_WIDTH :: 10
BOID_HEIGHT :: 20
BOID_VELOCITY :: 50

DEBUG_MODE :: false

Boid :: struct {
    vs: [3]rl.Vector2,
    // we need those to rotate around the local origin -> center of the triangle
    // otherwise we will be rotating around screen origin -> upper left corner of the screen
    base_vs: [3]rl.Vector2,
    pos: rl.Vector2,
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

update_boid_position :: proc(boid: ^Boid, dt: f32) {
    // friction := rl.Vector2{0.98, 0.98}

    heading_vector := rl.Vector2{math.cos_f32(boid.heading-(math.PI/2.0)), math.sin_f32(boid.heading-(math.PI/2.0))}

    boid.pos.x += heading_vector.x * BOID_VELOCITY * dt 
    boid.pos.y += heading_vector.y * BOID_VELOCITY * dt 

    if boid.pos.x > SCREEN_WIDTH {
        boid.pos.x = 0
    } else if boid.pos.x < 0 {
        boid.pos.x = SCREEN_WIDTH
    }

    if boid.pos.y > SCREEN_HEIGHT{
        boid.pos.y = 0
    } else if boid.pos.y < 0 {
        boid.pos.y = SCREEN_HEIGHT
    }
}

update_boid_rotation :: proc(boid: ^Boid, dt: f32) {
    speed := math.sqrt(boid.vel.x * boid.vel.x + boid.vel.y * boid.vel.y)
    rotationSpeed : f32 = 6
    targetHeading : f32

    // just want to check whether disabling this check will enable rotation for standing by boids
    if speed > 0.1 {
        offset : f32 = math.PI / 2.0

        // here the velocity is the target heading
        // we can grab the angle for which we need to rotate in radian with atan2
        // offset needed to compensate for initial drawing of the triangle, which is pointing upwards
        targetHeading = math.atan2(boid.vel.y, boid.vel.x) + offset
        diff := targetHeading - boid.heading

        for diff > math.PI { diff -= 2 * math.PI }
        for diff < -math.PI { diff += 2 * math.PI }
        
        if math.abs(diff) < rotationSpeed * dt {
            boid.heading = targetHeading
        } else {
            boid.heading += math.sign(diff) * rotationSpeed * dt
        }
    }    

    for &v, i in boid.base_vs {
        // this is basically the formula to rotate a triangle around the origin
        // the origin in this case is the "center" of the triangle
        xdt := v.x * math.cos(boid.heading) - v.y * math.sin(boid.heading)
        ydt := v.x * math.sin(boid.heading) + v.y * math.cos(boid.heading)
        rotationDt := rl.Vector2{ xdt, ydt }
        boid.vs[i] = rotationDt
    }
}

create_boid_at_random_position :: proc() -> (boid: Boid) {  
    boundaries :: [2]rl.Vector2{
        { 60, 80 },
        { SCREEN_WIDTH - 60, SCREEN_HEIGHT - 80 },
    }
    random_pos := rl.Vector2{ rand.float32_range(boundaries[0].x, boundaries[1].x), rand.float32_range(boundaries[0].y, boundaries[1].y) }

    boid.heading = rand.float32_range(f32(-math.PI), f32(math.PI))
    boid.pos = random_pos    
    boid.vel = rl.Vector2{ 0, 0} 
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
    // boid.heading = 0.0
    boid.vision_range = 80.0
    boid.protected_range = 30.0
    
    return
}

main :: proc() {
    acceleration : f32 : 10.0
    velocity ::  rl.Vector2{ 0, 0 }

    dt : f32 = 0.0
    dt = rl.GetFrameTime()

    boids : [10]Boid
    for &b, i in boids {
        b = create_boid_at_random_position()
    }

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Window")

    rl.SetTargetFPS(TARGET_FPS)

    for !rl.WindowShouldClose() {
        dt = rl.GetFrameTime()

        for &b, i in boids {
            update_boid_position(&b, dt)
            update_boid_rotation(&b, dt)
        }

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
