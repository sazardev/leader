// Every quad of a frame in one instanced draw: rectangles, glyphs from the atlas, underline styles.
struct Globals {
    screen: vec2<f32>,
    // 1.0 when the surface is sRGB (colors are converted to linear before blending).
    linear: f32,
    _pad: f32,
};

@group(0) @binding(0) var<uniform> g: Globals;
@group(0) @binding(1) var atlas: texture_2d<f32>;

struct In {
    @builtin(vertex_index) vi: u32,
    @location(0) pos: vec2<f32>,
    @location(1) size: vec2<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) color: vec4<f32>,
    @location(4) kind: u32,
};

struct Out {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) local: vec2<f32>,
    @location(2) color: vec4<f32>,
    @location(3) @interpolate(flat) kind: u32,
    @location(4) @interpolate(flat) size: vec2<f32>,
    @location(5) @interpolate(flat) uvw: f32,
};

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    let lo = c / 12.92;
    let hi = pow((c + 0.055) / 1.055, vec3<f32>(2.4));
    return select(hi, lo, c <= vec3<f32>(0.04045));
}

@vertex
fn vs(i: In) -> Out {
    let corner = vec2<f32>(f32(i.vi & 1u), f32(i.vi >> 1u));
    let px = i.pos + corner * i.size;
    var o: Out;
    o.position = vec4<f32>(px.x / g.screen.x * 2.0 - 1.0, 1.0 - px.y / g.screen.y * 2.0, 0.0, 1.0);
    o.uv = i.uv + corner * i.size;
    o.local = corner * i.size;
    var color = i.color;
    if (g.linear > 0.5) {
        color = vec4<f32>(to_linear(color.rgb), color.a);
    }
    o.color = color;
    o.kind = i.kind;
    o.size = i.size;
    o.uvw = i.uv.x;
    return o;
}

@fragment
fn fs(o: Out) -> @location(0) vec4<f32> {
    switch o.kind {
        case 1u: {
            let t = textureLoad(atlas, vec2<i32>(o.uv), 0);
            return vec4<f32>(o.color.rgb, o.color.a * t.a);
        }
        case 2u: {
            var t = textureLoad(atlas, vec2<i32>(o.uv), 0);
            if (g.linear > 0.5) {
                t = vec4<f32>(to_linear(t.rgb), t.a);
            }
            return t;
        }
        case 3u: {
            // Undercurl: one sine period every 6 px, antialiased by distance to the curve.
            let h = o.size.y;
            let center = h * 0.5 + sin(o.local.x * 6.2831853 / 6.0) * (h * 0.5 - 1.0);
            let a = clamp(1.2 - abs(o.local.y - center), 0.0, 1.0);
            return vec4<f32>(o.color.rgb, o.color.a * a);
        }
        case 4u: {
            let on = select(0.0, 1.0, (u32(o.local.x) % 4u) < 2u);
            return vec4<f32>(o.color.rgb, o.color.a * on);
        }
        case 5u: {
            let on = select(0.0, 1.0, (u32(o.local.x) % 8u) < 5u);
            return vec4<f32>(o.color.rgb, o.color.a * on);
        }
        case 6u: {
            // Close button's X: distance to both diagonals, uv.x = line width.
            let w = o.size.x;
            let d = min(abs(o.local.x - o.local.y), abs(o.local.x + o.local.y - w)) * 0.70710678;
            let a = clamp(o.uvw * 0.5 + 0.5 - d, 0.0, 1.0);
            return vec4<f32>(o.color.rgb, o.color.a * a);
        }
        case 7u: {
            // A dot of the mark: coverage of a disc the size of the quad.
            let d = length(o.local - o.size * 0.5);
            let a = clamp(o.size.x * 0.5 - d + 0.5, 0.0, 1.0);
            return vec4<f32>(o.color.rgb, o.color.a * a);
        }
        default: {
            return o.color;
        }
    }
}
