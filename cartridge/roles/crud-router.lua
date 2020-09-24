local vshard = require('vshard')
local crud = require('crud')

-- CRUD functions wrappers
local function crud_get(space_name, key, opts)
    return crud.get(space_name, key, opts)
end

local function crud_insert(space_name, obj, opts)
    return crud.insert(space_name, obj, opts)
end

local function crud_delete(space_name, key, opts)
    return crud.delete(space_name, key, opts)
end

local function crud_replace(space_name, obj, opts)
    return crud.replace(space_name, obj, opts)
end

local function crud_update(space_name, key, operations, opts)
    return crud.update(space_name, key, operations, opts)
end

local function crud_upsert(space_name, obj, operations, opts)
    return crud.upsert(space_name, obj, operations, opts)
end

local function crud_select(space_name, user_conditions, opts)
    local objects, err = crud.select(space_name, user_conditions, opts)
    if err ~= nil then
        return nil, err
    else
        return unpack(objects)
    end
end

-- function to get cluster schema
local function crud_get_schema()
    local replicaset = select(2, next(vshard.router.routeall()))
    local uniq_spaces = {}
    local spaces_ids = {}
    for _, space in pairs(replicaset.master.conn.space) do
        if (spaces_ids[space.id] == nil) then
            table.insert(t, { space })
            spaces_ids[space.id] = true
        end
    end
    return uniq_spaces
end

-- removes routes that changed in config and adds new routes
local function init()
    crud.init({
        tuples_as_map = false,
    })

    rawset(_G, 'crud_get', crud_get)
    rawset(_G, 'crud_insert', crud_insert)
    rawset(_G, 'crud_delete', crud_delete)
    rawset(_G, 'crud_replace', crud_replace)
    rawset(_G, 'crud_update', crud_update)
    rawset(_G, 'crud_upsert', crud_upsert)
    rawset(_G, 'crud_select', crud_select)
end

return {
    role_name = 'crud-router',
    init = init,
    dependencies = { 'cartridge.roles.vshard-router' }
}
