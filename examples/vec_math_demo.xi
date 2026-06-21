// std/vec — fixed-size math vectors (Vec2/Vec3/Vec4) and linear algebra.
// (Distinct from the Vec<T> dynamic-array container.)
//
//   xc examples/vec_math_demo.xi && ./build/vec_math_demo
import "std/log.xi"
import "std/vec.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    let a = vec.v3(1.0, 2.0, 3.0)
    let b = vec.v3(4.0, 5.0, 6.0)

    logger.info("a + b   = " + vec.add3(a, b).x + "," + vec.add3(a, b).y + "," + vec.add3(a, b).z)
    logger.info("a . b   = " + vec.dot3(a, b))                 // 32
    let c = vec.cross3(a, b)
    logger.info("a x b   = " + c.x + "," + c.y + "," + c.z)    // -3, 6, -3
    logger.info("|3,4,0| = " + vec.length3(vec.v3(3.0, 4.0, 0.0)))   // 5

    let n = vec.normalize3(vec.v3(0.0, 3.0, 4.0))
    logger.info("normalize(0,3,4) = " + n.x + "," + n.y + "," + n.z) // 0, 0.6, 0.8

    let mid = vec.lerp2(vec.v2(0.0, 0.0), vec.v2(10.0, 20.0), 0.5)
    logger.info("lerp midpoint = " + mid.x + "," + mid.y)      // 5, 10
    return 0
}

module App {}
