package main

import rl"vendor:raylib"
import "core:math"

screenWidth :: 800;
screenHeight :: 600;
targetFPS :: 60;

Boid :: struct {
    vs: [3]rl.Vector2,
    pos: rl.Vector2,
    vel: rl.Vector2,
    a: rl.Vector2,
    heading: f32
}

DrawBoid :: proc(boid: Boid) {
    rl.DrawTriangle(boid.vs[0], boid.vs[1], boid.vs[2], rl.MAROON); 
}

UpdateBoidPosition :: proc(boid: ^Boid, dt: f32) {
    friction := rl.Vector2{0.98, 0.98};

    boid.vel.x += boid.a.x;
    boid.vel.y += boid.a.y;
    boid.vel *= friction;
    boid.pos.x += boid.vel.x * dt; 
    boid.pos.y += boid.vel.y * dt; 

    if boid.pos.x > screenWidth {
        boid.pos.x = 0;
    } else if boid.pos.x < 0 {
        boid.pos.x = screenWidth;
    }

    if boid.pos.y > screenHeight{
        boid.pos.y = 0;
    } else if boid.pos.y < 0 {
        boid.pos.y = screenHeight;
    }

    boid.vs = [3]rl.Vector2{
            {boid.pos.x, boid.pos.y-50},
            {boid.pos.x-50, boid.pos.y+50},
            {boid.pos.x+50, boid.pos.y+50},
    };
}

UpdateBoidRotation :: proc(boid: ^Boid, dt: f32) {
    speed := math.sqrt(boid.vel.x * boid.vel.x + boid.vel.y * boid.vel.y)
    rotationSpeed : f32 = 6;
    targetHeading : f32;

    if speed > 0.1 {
        offset : f32 = math.PI / 2.0;

        // here the velocity is the target heading
        // we can grab the angle for which we need to rotate in radian with atan2
        // offset needed to compensate for initial drawing of the triangle, which is pointing upwards
        targetHeading = math.atan2(boid.vel.y, boid.vel.x) + offset;
        diff := targetHeading - boid.heading;

        for diff > math.PI { diff -= 2 * math.PI; }
        for diff < -math.PI { diff += 2 * math.PI; }
        
        if math.abs(diff) < rotationSpeed * dt {
            boid.heading = targetHeading;
        } else {
            boid.heading += math.sign(diff) * rotationSpeed * dt;
        }
    }

    // we need those to rotate around the local origin -> center of the triangle
    // otherwise we will be rotating around screen origin -> upper left corner of the screen
    local_vs := [3]rl.Vector2{
        {0, -50},
        {-50, 50},
        {50, 50}
    };
    
    for &v, i in local_vs {
        // this is basically the formula to rotate a triangle around the origin
        // the origin in this case is the "center" of the triangle
        xdt := v.x * math.cos(boid.heading) - v.y * math.sin(boid.heading);
        ydt := v.x * math.sin(boid.heading) + v.y * math.cos(boid.heading);
        boid.vs[i].x = xdt + boid.pos.x;
        boid.vs[i].y = ydt + boid.pos.y;
    }
}

main :: proc() {
    acceleration : f32 = 10.0;
    boid : Boid;
    boid.pos = rl.Vector2{screenWidth/2, screenHeight/3};
    boid.vel = rl.Vector2{0, 0};
    boid.a = rl.Vector2{0, 0};
    boid.vs = [3]rl.Vector2{
            {boid.pos.x, boid.pos.y-50},
            {boid.pos.x-50, boid.pos.y+50},
            {boid.pos.x+50, boid.pos.y+50},
        };
    boid.heading = 0.0;
    dt : f32 = 0.0;

    rl.InitWindow(screenWidth, screenHeight, "Window");

    rl.SetTargetFPS(targetFPS);

    for !rl.WindowShouldClose() {
        dt = rl.GetFrameTime();
        boid.a = rl.Vector2{0, 0};

        if rl.IsKeyDown(rl.KeyboardKey.RIGHT)  {
            boid.a.x += acceleration;
        }

        if rl.IsKeyDown(rl.KeyboardKey.LEFT) {
            boid.a.x -= acceleration;
        }

        if rl.IsKeyDown(rl.KeyboardKey.DOWN) {
            boid.a.y += acceleration;
        }

        if rl.IsKeyDown(rl.KeyboardKey.UP) {
            boid.a.y -= acceleration;
        }

        UpdateBoidPosition(&boid, dt);
        UpdateBoidRotation(&boid, dt);

        rl.BeginDrawing(); 

        rl.ClearBackground(rl.RAYWHITE);

        DrawBoid(boid);

        rl.EndDrawing();
    }

    rl.CloseWindow();
}
