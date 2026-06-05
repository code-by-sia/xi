// std/xml — XML serialization over the Json value tree.  import "std/xml.xi"
//
// Build/read values with std/json; render or parse XML here. Convention: an
// object becomes child elements (one per key), an array repeats its element,
// and a scalar becomes text. `stringify` wraps the value in a <root> element
// (use `stringifyAs` for a different name); `parse` returns the root element's
// value. Attributes are ignored on parse and not emitted; entities
// (&lt; &gt; &amp; &quot; &apos;) are handled.
namespace xml

extern "C" {
    mapper    xstd_xml_stringify(v: Json) -> String
    mapper    xstd_xml_stringify_as(v: Json, root: String) -> String
    producer  xstd_xml_parse(s: String) -> Json
}

mapper   stringify(v: Json) -> String                  { return xstd_xml_stringify(v) }
mapper   stringifyAs(v: Json, root: String) -> String  { return xstd_xml_stringify_as(v, root) }
producer parse(s: String) -> Json                      { return xstd_xml_parse(s) }
