// std/io — console input/output.  import "std/io.x"  then  io.println("hi")
namespace io

extern "C" {
    producer  read_line() -> String
    predicate stdin_eof() -> Bool
}

consumer println(s: String) { system.stdout.writeln(s) }
consumer print(s: String)   { system.stdout.write(s) }
consumer eprintln(s: String) { system.stderr.writeln(s) }

// Read a line from stdin (newline stripped).  Pair with io.eof().
producer readLine() -> String { return read_line() }
predicate eof() { return stdin_eof() }
