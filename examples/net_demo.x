// TCP sockets: a self-contained loopback echo (client + server in one process).
// Works single-threaded because the kernel buffers the small messages.
import "std/net.x"

async entry main(args: String[]) -> Integer {
    let lr = net.listen(0)            // 0 = OS-assigned ephemeral port
    if isErr(lr) { system.stderr.writeln("listen: " + lr.err) return 1 }
    let server = lr.value
    let p = net.port(server)

    let cr = net.dial("127.0.0.1", p)
    if isErr(cr) { system.stderr.writeln("dial: " + cr.err) return 1 }
    let client = cr.value

    let ar = net.accept(server)       // pick up the pending connection
    if isErr(ar) { system.stderr.writeln("accept: " + ar.err) return 1 }
    let peer = ar.value

    net.sendText(client, "hello")
    let req = net.recvText(peer, 256)
    net.sendText(peer, "echo:" + req)
    let resp = net.recvText(client, 256)

    system.stdout.writeln("server saw:  " + req)
    system.stdout.writeln("client got:  " + resp)

    net.close(client)
    net.close(peer)
    net.closeListener(server)
    return 0
}
