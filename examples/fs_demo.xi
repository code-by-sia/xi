// Filesystem + path standard library.
import "std/log.xi"
import "std/fs.xi"
import "std/path.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
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
    if isOk(note) { logger.print("notes: " + note.value) }

    let data = fs.readBytes(dir + "/data.bin")
    if isOk(data) { logger.print("data bytes: " + bytes.length(data.value)) }

    let sz = fs.size(dir + "/notes.txt")
    if isOk(sz) { logger.print("notes size: " + sz.value) }

    // Path helpers.
    let p = "/usr/local/bin/xc.x"
    logger.print("dirname:  " + path.dirname(p))
    logger.print("basename: " + path.basename(p))
    logger.print("ext:      " + path.ext(p))
    logger.print("join:     " + path.join(dir, "notes.txt"))

    // Cleanup.
    fs.remove(dir + "/notes.txt")
    fs.remove(dir + "/data.bin")
    logger.print("cleaned:  " + fs.exists(dir + "/notes.txt"))
    return 0
}
