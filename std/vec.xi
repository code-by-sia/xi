// std/vec — fixed-size math vectors (2D/3D/4D) with a linear-algebra API.
// Distinct from the `Vec<T>` dynamic-array container. Use as:
//   import "std/vec.xi"   then   vec.v3(1.0, 2.0, 3.0)   vec.dot3(a, b)
namespace vec

import "std/math.xi"

type Vec2 = { x: Number, y: Number }
type Vec3 = { x: Number, y: Number, z: Number }
type Vec4 = { x: Number, y: Number, z: Number, w: Number }

// ── constructors ─────────────────────────────────────────────────────────────
creator v2(x: Number, y: Number) -> Vec2                         => Vec2 { x: x, y: y }
creator v3(x: Number, y: Number, z: Number) -> Vec3             => Vec3 { x: x, y: y, z: z }
creator v4(x: Number, y: Number, z: Number, w: Number) -> Vec4  => Vec4 { x: x, y: y, z: z, w: w }

// ── Vec2 ─────────────────────────────────────────────────────────────────────
mapper add2(a: Vec2, b: Vec2) -> Vec2   => Vec2 { x: a.x + b.x, y: a.y + b.y }
mapper sub2(a: Vec2, b: Vec2) -> Vec2   => Vec2 { x: a.x - b.x, y: a.y - b.y }
mapper scale2(a: Vec2, s: Number) -> Vec2 => Vec2 { x: a.x * s, y: a.y * s }
mapper neg2(a: Vec2) -> Vec2            => Vec2 { x: 0.0 - a.x, y: 0.0 - a.y }
mapper dot2(a: Vec2, b: Vec2) -> Number => a.x * b.x + a.y * b.y
mapper lengthSq2(a: Vec2) -> Number     => a.x * a.x + a.y * a.y
mapper length2(a: Vec2) -> Number       => math.sqrt(a.x * a.x + a.y * a.y)
mapper distance2(a: Vec2, b: Vec2) -> Number => length2(sub2(a, b))
mapper normalize2(a: Vec2) -> Vec2 {
    let len = length2(a)
    if len == 0.0 { return a }
    return Vec2 { x: a.x / len, y: a.y / len }
}
mapper lerp2(a: Vec2, b: Vec2, t: Number) -> Vec2 {
    return Vec2 { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }
}

// ── Vec3 ─────────────────────────────────────────────────────────────────────
mapper add3(a: Vec3, b: Vec3) -> Vec3   => Vec3 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }
mapper sub3(a: Vec3, b: Vec3) -> Vec3   => Vec3 { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }
mapper scale3(a: Vec3, s: Number) -> Vec3 => Vec3 { x: a.x * s, y: a.y * s, z: a.z * s }
mapper neg3(a: Vec3) -> Vec3            => Vec3 { x: 0.0 - a.x, y: 0.0 - a.y, z: 0.0 - a.z }
mapper dot3(a: Vec3, b: Vec3) -> Number => a.x * b.x + a.y * b.y + a.z * b.z
mapper cross3(a: Vec3, b: Vec3) -> Vec3 {
    return Vec3 {
        x: a.y * b.z - a.z * b.y,
        y: a.z * b.x - a.x * b.z,
        z: a.x * b.y - a.y * b.x
    }
}
mapper lengthSq3(a: Vec3) -> Number     => a.x * a.x + a.y * a.y + a.z * a.z
mapper length3(a: Vec3) -> Number       => math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
mapper distance3(a: Vec3, b: Vec3) -> Number => length3(sub3(a, b))
mapper normalize3(a: Vec3) -> Vec3 {
    let len = length3(a)
    if len == 0.0 { return a }
    return Vec3 { x: a.x / len, y: a.y / len, z: a.z / len }
}
mapper lerp3(a: Vec3, b: Vec3, t: Number) -> Vec3 {
    return Vec3 { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t }
}

// ── Vec4 ─────────────────────────────────────────────────────────────────────
mapper add4(a: Vec4, b: Vec4) -> Vec4   => Vec4 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, w: a.w + b.w }
mapper sub4(a: Vec4, b: Vec4) -> Vec4   => Vec4 { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z, w: a.w - b.w }
mapper scale4(a: Vec4, s: Number) -> Vec4 => Vec4 { x: a.x * s, y: a.y * s, z: a.z * s, w: a.w * s }
mapper dot4(a: Vec4, b: Vec4) -> Number => a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
mapper lengthSq4(a: Vec4) -> Number     => a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w
mapper length4(a: Vec4) -> Number       => math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z + a.w * a.w)
