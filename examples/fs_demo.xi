// Filesystem + path standard library.
import "std/fs.xi"
import "std/path.xi"

async entry main(args: String[]) -> Integer {
    let dir = "/tmp/x_fs_demo"

    // Start clean, then create a directory tree.
    fs.remove(dir + "/notes.txt")
    fs.remove(dir + "/data.bin")
    fs.mkdirAll(dir)

    // Text and binary writes.
    fs.writeFile(dir + "/notes.txt", "first line")
    fs.appendLine(dir + "/notes.txt", "")          // newline after first
    fs.writeBytes(dir + "/data.bin", bytes.fromString("raw"))

    // Read them back.
    let note = fs.readFile(dir + "/notes.txt")
    if isOk(note) { system.stdout.write("notes: " + note.value) }

    let data = fs.readBytes(dir + "/data.bin")
    if isOk(data) { system.stdout.writeln("data bytes: " + bytes.length(data.value)) }

    let sz = fs.size(dir + "/notes.txt")
    if isOk(sz) { system.stdout.writeln("notes size: " + sz.value) }

    // Path helpers.
    let p = "/usr/local/bin/xc.x"
    system.stdout.writeln("dirname:  " + path.dirname(p))
    system.stdout.writeln("basename: " + path.basename(p))
    system.stdout.writeln("ext:      " + path.ext(p))
    system.stdout.writeln("join:     " + path.join(dir, "notes.txt"))

    // Cleanup.
    fs.remove(dir + "/notes.txt")
    fs.remove(dir + "/data.bin")
    system.stdout.writeln("cleaned:  " + fs.exists(dir + "/notes.txt"))
    return 0
}
