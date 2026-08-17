module uniconfig.core.merge;

import std.json : JSONType, JSONValue;
import uniconfig.core.tree;
import uniconfig.core.schema;

/// Overlay schema fields onto a file tree. Unset optional fields stay visible (`fromSchema`, `included=false`).
ConfigNode mergeSchema(ConfigNode fileRoot, DocumentSchema schema)
{
    auto outRoot = new ConfigNode;
    outRoot.key = fileRoot ? fileRoot.key : "";
    outRoot.path = "";
    outRoot.fromFile = fileRoot !is null;
    outRoot.fromSchema = true;
    outRoot.included = true;
    outRoot.title = schema.title;
    outRoot.schemaType = "object";
    if (schema.root.description.length)
        outRoot.description = schema.root.description;

    applyObject(outRoot, fileRoot, schema.root);
    // Preserve extra file keys the schema does not mention.
    if (fileRoot !is null)
    {
        foreach (c; fileRoot.children)
        {
            if (outRoot.child(c.key) is null)
            {
                c.fromFile = true;
                outRoot.putChild(c);
            }
        }
    }
    return outRoot;
}

private void applyObject(ConfigNode dest, ConfigNode fileNode, FieldSchema schema)
{
    foreach (prop; schema.properties)
    {
        auto existing = fileNode ? fileNode.child(prop.name) : null;
        auto n = new ConfigNode;
        n.key = prop.name;
        n.path = prop.path.length ? prop.path : joinPath(dest.path, prop.name);
        n.title = prop.title.length ? prop.title : prop.name;
        n.description = prop.description;
        n.enumValues = prop.enumValues.dup;
        n.schemaType = prop.type;
        n.required = prop.required;
        n.fromSchema = true;
        if (existing !is null)
        {
            n.fromFile = true;
            n.included = true;
            n.value = existing.value;
            n.children = existing.children;
        }
        else
        {
            n.fromFile = false;
            n.included = prop.required;
            n.value = prop.defaultValue;
        }
        if (prop.type == "object" || prop.properties.length)
            applyObject(n, existing, prop);
        dest.putChild(n);
    }
}

FieldSchema[] missingFields(ConfigNode merged)
{
    FieldSchema[] acc;
    void rec(ConfigNode n)
    {
        if (n.fromSchema && !n.fromFile && n.children.length == 0)
        {
            FieldSchema f;
            f.name = n.key;
            f.path = n.path;
            f.type = n.schemaType;
            f.title = n.title;
            f.description = n.description;
            f.enumValues = n.enumValues.dup;
            f.required = n.required;
            acc ~= f;
        }
        foreach (c; n.children)
            rec(c);
    }
    rec(merged);
    return acc;
}

unittest
{
    auto file = nodeFromJson(JSONValue(["user.name": JSONValue("ada")]));
    // nested reconstruction
    auto nested = new ConfigNode;
    auto user = new ConfigNode;
    user.key = "user";
    user.path = "user";
    user.fromFile = true;
    auto name = new ConfigNode;
    name.key = "name";
    name.path = "user.name";
    name.value = JSONValue("ada");
    name.fromFile = true;
    user.putChild(name);
    nested.putChild(user);

    DocumentSchema ds;
    ds.title = "git";
    FieldSchema userS;
    userS.name = "user";
    userS.path = "user";
    userS.type = "object";
    FieldSchema nameS;
    nameS.name = "name";
    nameS.path = "user.name";
    nameS.type = "string";
    FieldSchema emailS;
    emailS.name = "email";
    emailS.path = "user.email";
    emailS.type = "string";
    emailS.description = "Public email";
    userS.properties = [nameS, emailS];
    ds.root.properties = [userS];

    auto m = mergeSchema(nested, ds);
    auto email = m.childAt("user.email");
    assert(email !is null);
    assert(email.fromSchema);
    assert(!email.fromFile);
    assert(missingFields(m).length >= 1);
}
