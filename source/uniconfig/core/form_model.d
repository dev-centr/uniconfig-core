module uniconfig.core.form_model;

import uniconfig.core.tree;

/// Toolkit-neutral control kind for binders (Qt, GTK, dui, web, …).
enum FormControlKind
{
    sectionHeader,
    boolean_,
    choice,
    text,
}

/// One render row — binders map this to native widgets.
struct FormRow
{
    FormControlKind kind;
    ConfigNode node;
    int depth;
    bool showIncludeToggle;
    string label;
}

FormControlKind controlKind(const ConfigNode n)
{
    import std.json : JSONType;
    if (n.children.length)
        return FormControlKind.sectionHeader;
    if (n.schemaType == "boolean" || n.value.type == JSONType.true_
            || n.value.type == JSONType.false_)
        return FormControlKind.boolean_;
    if (n.enumValues.length)
        return FormControlKind.choice;
    return FormControlKind.text;
}

string rowLabel(const ConfigNode n)
{
    string label = n.title.length ? n.title : n.key;
    if (n.required)
        label ~= " *";
    if (!n.fromFile && n.fromSchema)
        label ~= "  (unset)";
    return label;
}

FormRow[] flattenFormRows(ConfigNode root)
{
    FormRow[] rows;
    void walk(ConfigNode node, int depth)
    {
        foreach (c; node.children)
        {
            auto kind = controlKind(c);
            if (kind == FormControlKind.sectionHeader)
            {
                rows ~= FormRow(kind, c, depth, false, rowLabel(c));
                walk(c, depth + 1);
                continue;
            }
            rows ~= FormRow(kind, c, depth, c.fromSchema && !c.fromFile, rowLabel(c));
        }
    }
    if (root !is null)
        walk(root, 0);
    return rows;
}

unittest
{
    import std.json : JSONValue;
    auto root = nodeFromJson(JSONValue(["a": JSONValue(true)]));
    auto rows = flattenFormRows(root);
    assert(rows.length == 1);
    assert(rows[0].kind == FormControlKind.boolean_);
}
