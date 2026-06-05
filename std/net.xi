// std/net — TCP sockets (blocking).  import "std/net.xi"
//   client:  let c = net.dial("example.com", 80)
//   server:  let l = net.listen(0)  then  net.accept(l)
namespace net

import "std/bytes.xi"

extern "C" {
    producer xstd_tcp_connect(host: String, port: Integer) -> Integer
    producer xstd_tcp_listen(port: Integer, backlog: Integer) -> Integer
    producer xstd_tcp_accept(fd: Integer) -> Integer
    mapper   xstd_sock_port(fd: Integer) -> Integer
    producer xstd_sock_send(fd: Integer, data: Bytes) -> Integer
    producer xstd_sock_recv(fd: Integer, max: Integer) -> Bytes
    producer xstd_sock_close(fd: Integer) -> Bool
}

type Conn     = { fd: Integer }
type Listener = { fd: Integer }

// Connect to host:port.
producer dial(host: String, port: Integer) -> Conn! {
    let fd = xstd_tcp_connect(host, port)
    if fd < 0 { return err("connect failed: " + host + ":" + port) }
    return ok(Conn { fd: fd })
}

// Listen on a port (use 0 for an OS-assigned ephemeral port; read it with port()).
producer listen(port: Integer) -> Listener! {
    let fd = xstd_tcp_listen(port, 16)
    if fd < 0 { return err("listen failed on port " + port) }
    return ok(Listener { fd: fd })
}

// Accept the next incoming connection (blocks).
producer accept(l: Listener) -> Conn! {
    let fd = xstd_tcp_accept(l.fd)
    if fd < 0 { return err("accept failed") }
    return ok(Conn { fd: fd })
}

// The local port a listener is bound to.
mapper port(l: Listener) -> Integer { return xstd_sock_port(l.fd) }

producer send(c: Conn, data: Bytes) -> Integer { return xstd_sock_send(c.fd, data) }
producer sendText(c: Conn, s: String) -> Integer { return xstd_sock_send(c.fd, bytes.fromString(s)) }
producer recv(c: Conn, max: Integer) -> Bytes { return xstd_sock_recv(c.fd, max) }
producer recvText(c: Conn, max: Integer) -> String { return bytes.toString(xstd_sock_recv(c.fd, max)) }

consumer close(c: Conn) { xstd_sock_close(c.fd) }
consumer closeListener(l: Listener) { xstd_sock_close(l.fd) }
