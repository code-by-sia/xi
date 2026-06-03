// std/fs — filesystem.  import "std/fs.x"  then  fs.readFile(path)
namespace fs

import "std/bytes.x"

extern "C" {
    producer  file_read_all(path: String) -> String
    producer  file_write(path: String, content: String) -> Bool
    producer  file_writeln(path: String, line: String) -> Bool
    predicate xstd_file_exists(path: String) -> Bool
    producer  xstd_read_bytes(path: String) -> Bytes
    producer  xstd_write_bytes(path: String, b: Bytes) -> Bool
    predicate xstd_is_dir(path: String) -> Bool
    predicate xstd_is_file(path: String) -> Bool
    mapper    xstd_file_size(path: String) -> Integer
    mapper    xstd_mtime(path: String) -> Integer
    producer  xstd_remove(path: String) -> Bool
    producer  xstd_rename(from: String, to: String) -> Bool
    producer  xstd_mkdir(path: String) -> Bool
    producer  xstd_mkdir_all(path: String) -> Bool
    producer  xstd_cwd() -> String
    producer  xstd_list_dir(path: String) -> String[]
}

predicate exists(path: String) { return xstd_file_exists(path) }
predicate isDir(path: String)  { return xstd_is_dir(path) }
predicate isFile(path: String) { return xstd_is_file(path) }

// Read a whole file as text, or Err if it does not exist.
producer readFile(path: String) -> String! {
    if xstd_file_exists(path) { return ok(file_read_all(path)) }
    return err("file not found: " + path)
}

// Read a file as raw bytes, or Err if it does not exist.
producer readBytes(path: String) -> Bytes! {
    if xstd_file_exists(path) { return ok(xstd_read_bytes(path)) }
    return err("file not found: " + path)
}

producer writeFile(path: String, content: String) -> Bool { return file_write(path, content) }
producer writeBytes(path: String, b: Bytes) -> Bool { return xstd_write_bytes(path, b) }
producer appendLine(path: String, line: String) -> Bool { return file_writeln(path, line) }

// Size in bytes, or Err if the path doesn't exist.
producer size(path: String) -> Integer! {
    let n = xstd_file_size(path)
    if n < 0 { return err("no such file: " + path) }
    return ok(n)
}

// Last-modified time (epoch seconds), or Err if the path doesn't exist.
producer modifiedTime(path: String) -> Integer! {
    let t = xstd_mtime(path)
    if t < 0 { return err("no such file: " + path) }
    return ok(t)
}

producer remove(path: String) -> Bool { return xstd_remove(path) }
producer rename(from: String, to: String) -> Bool { return xstd_rename(from, to) }
producer mkdir(path: String) -> Bool { return xstd_mkdir(path) }
producer mkdirAll(path: String) -> Bool { return xstd_mkdir_all(path) }
producer cwd() -> String { return xstd_cwd() }

// List directory entries (names only, excluding "." and ".."). Empty if `path`
// is not a directory. (Result-of-array isn't supported by codegen yet, so this
// returns the array directly; check fs.isDir first if you need to distinguish.)
producer listDir(path: String) -> String[] {
    return xstd_list_dir(path)
}

// Copy a file's bytes to a new path.
producer copy(from: String, to: String) -> Bool {
    if xstd_file_exists(from) { return xstd_write_bytes(to, xstd_read_bytes(from)) }
    return false
}
