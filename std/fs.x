// std/fs — filesystem.  import "std/fs.x"  then  fs.readFile(path)
namespace fs

extern "C" {
    producer  file_read_all(path: String) -> String
    producer  file_write(path: String, content: String) -> Bool
    producer  file_writeln(path: String, line: String) -> Bool
    predicate xstd_file_exists(path: String) -> Bool
}

predicate exists(path: String) { return xstd_file_exists(path) }

// Read a whole file, or Err if it does not exist.
producer readFile(path: String) -> String! {
    if xstd_file_exists(path) { return ok(file_read_all(path)) }
    return err("file not found: " + path)
}

producer writeFile(path: String, content: String) -> Bool { return file_write(path, content) }
producer appendLine(path: String, line: String) -> Bool { return file_writeln(path, line) }
