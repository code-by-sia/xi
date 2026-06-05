// std/yaml — YAML serialization over the Json value tree.  import "std/yaml.xi"
//
// Build/read values with std/json; render or parse YAML here. Supports block
// style: mappings, sequences, scalars, nesting, and `#` comments. (Flow style,
// anchors, multi-line scalars, and inline comments are not supported.)
namespace yaml

extern "C" {
    mapper    xstd_yaml_stringify(v: Json) -> String
    producer  xstd_yaml_parse(s: String) -> Json
}

mapper   stringify(v: Json) -> String { return xstd_yaml_stringify(v) }
producer parse(s: String) -> Json     { return xstd_yaml_parse(s) }
