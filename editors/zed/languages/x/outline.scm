; Symbols shown in Zed's outline panel.

(type_decl
  "type" @context
  name: (identifier) @name) @item

(interface_decl
  "interface" @context
  name: (identifier) @name) @item

(class_decl
  "class" @context
  name: (identifier) @name) @item

(module_decl
  "module" @context
  (qualified_name) @name) @item

(function_decl
  (function_kind) @context
  name: (identifier) @name) @item

(creator_decl
  "creator" @context
  name: (identifier) @name) @item

(entry_decl
  "entry" @context
  name: (identifier) @name) @item

(method_sig
  name: (identifier) @name) @item
