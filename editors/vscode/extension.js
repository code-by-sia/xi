// Lightweight completion for X: keywords / function kinds / types globally,
// and standard-library members after a namespace dot. No dependencies beyond
// the VS Code API (syntax highlighting comes from the TextMate grammar).
const vscode = require("vscode");

const KEYWORDS = [
  "if", "else", "match", "when", "otherwise", "for", "while", "loop",
  "break", "continue", "return", "scope", "unsafe", "spawn", "await",
  "async", "where", "hit", "let", "import", "export", "extern", "namespace",
  "type", "interface", "class", "implements", "extends", "deps", "module",
  "bind", "as", "and", "or", "not", "is", "in", "matches",
  "true", "false", "none", "self", "value", "singleton", "transient"
];
const KINDS = ["mapper", "projector", "predicate", "consumer", "producer", "reducer", "creator", "decision", "entry"];
const TYPES = ["Number", "Integer", "Bool", "String", "Char", "Bytes", "Void", "Size"];
const NAMESPACES = ["math", "text", "bytes", "convert", "io", "fs", "path", "net", "http", "proc", "time", "system"];

// Standard-library members, keyed by namespace.
const MEMBERS = {
  math: ["pi", "e", "abs", "sqrt", "exp", "ln", "log10", "sin", "cos", "tan", "floor", "ceil", "round", "pow"],
  text: ["length", "charAt", "substring", "trim", "toUpper", "toLower", "startsWith", "endsWith", "contains", "indexOf", "repeat", "replace", "isEmpty", "split", "join"],
  bytes: ["length", "at", "slice", "concat", "fromString", "toString", "empty", "isEmpty"],
  convert: ["toString", "intToString", "boolToString", "parseNumber", "parseInteger"],
  io: ["println", "print", "eprintln", "readLine", "eof"],
  fs: ["exists", "isDir", "isFile", "readFile", "readBytes", "writeFile", "writeBytes", "appendLine", "size", "modifiedTime", "remove", "rename", "copy", "mkdir", "mkdirAll", "cwd", "listDir"],
  path: ["join", "dirname", "basename", "ext", "stripExt"],
  net: ["dial", "listen", "accept", "port", "send", "sendText", "recv", "recvText", "close", "closeListener"],
  http: ["get", "post", "request", "header", "parseUrl", "parseResponse"],
  proc: ["env", "envOr", "run", "exit"],
  time: ["nowNanos", "nowMillis", "sleepMs"],
  system: ["stdout", "stderr"]
};
const STREAM_MEMBERS = ["writeln", "write"]; // system.stdout. / system.stderr.

function items(names, kind) {
  return names.map((n) => new vscode.CompletionItem(n, kind));
}

function activate(context) {
  const provider = vscode.languages.registerCompletionItemProvider(
    "x",
    {
      provideCompletionItems(document, position) {
        const prefix = document.lineAt(position).text.slice(0, position.character);

        // system.stdout. / system.stderr.
        if (/\bsystem\.(stdout|stderr)\.\s*$/.test(prefix)) {
          return items(STREAM_MEMBERS, vscode.CompletionItemKind.Method);
        }
        // <namespace>.
        const m = prefix.match(/\b([A-Za-z_][A-Za-z0-9_]*)\.\s*$/);
        if (m && MEMBERS[m[1]]) {
          return items(MEMBERS[m[1]], vscode.CompletionItemKind.Function);
        }
        if (m) return undefined; // a dot on something we don't know — stay quiet

        // global identifiers
        return [].concat(
          items(KEYWORDS, vscode.CompletionItemKind.Keyword),
          items(KINDS, vscode.CompletionItemKind.Keyword),
          items(TYPES, vscode.CompletionItemKind.TypeParameter),
          items(NAMESPACES, vscode.CompletionItemKind.Module)
        );
      }
    },
    "." // trigger member completion on dot
  );
  context.subscriptions.push(provider);
}

function deactivate() {}

module.exports = { activate, deactivate };
