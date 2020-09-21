local checks = require('checks')
local errors = require('errors')
local vshard = require('vshard')
local key_def_lib = require('key_def')

local call = require('elect.common.call')
local registry = require('elect.common.registry')
local utils = require('elect.common.utils')

local select_conditions = require('elect.select.conditions')
local select_plan = require('elect.select.plan')
local select_executor = require('elect.select.executor')

local Iterator = require('elect.select.iterator')

require('elect.common.checkers')

local SelectError = errors.new_class('Select', {capture_stack = false})

local select_module = {}

local SELECT_FUNC_NAME = '__select'

local function call_select_on_storage(space_name, conditions, opts)
    checks('string', '?table', {
        limit = '?number',
        after_tuple = '?table',
    })

    -- XXX: init cont_pairs in other place
    local ok, err = require('elect.cont_pairs').init()
    if not ok then
        return nil, SelectError:new("Failed to init cont_pairs: %s", err)
    end

    local space = box.space[space_name]
    if space == nil then
        return nil, SelectError:new("Space %s doesn't exists", space_name)
    end

    -- plan select
    local plan, err = select_plan.new(space, conditions, {
        limit = opts.limit,
        after_tuple = opts.after_tuple,
    })

    if err ~= nil then
        return nil, SelectError:new("Failed to plan select: %s", err)
    end

    -- execute select
    local tuples = select_executor.execute(plan)

    return tuples
end

function select_module.init()
    registry.add({
        [SELECT_FUNC_NAME] = call_select_on_storage,
    })
end

local function select_iteration(space_name, conditions, opts)
    checks('string', '?table', {
        after_tuple = '?table',
        limit = '?number',
        replicasets = 'table',
        timeout = '?number',
        batch_size = '?number',
    })

    -- call select on storages
    local storage_select_opts = {
        after_tuple = opts.after_tuple,
        limit = opts.batch_size,
    }

    local results, err = call.ro({
        func_name = SELECT_FUNC_NAME,
        func_args = {
            space_name, conditions, storage_select_opts,
        },
        replicasets = opts.replicasets,
        timeout = opts.timeout,
    })

    if err ~= nil then
        return nil, err
    end

    return results
end

function select_module.call(space_name, user_conditions, opts)
    checks('string', '?table', {
        after = '?',
        limit = '?number',
        timeout = '?number',
        batch_size = '?number',
    })

    opts = opts or {}

    if opts.batch_size ~= nil and opts.batch_size < 1 then
        return nil, SelectError:new("batch_size should be > 0")
    end

    if opts.limit ~= nil and opts.limit < 0 then
        return nil, SelectError:new("limit should be >= 0")
    end

    -- parse conditions
    local conditions, err = select_conditions.parse(user_conditions)
    if err ~= nil then
        return nil, SelectError:new("Failed to parse conditions: %s", err)
    end

    local replicasets, err = vshard.router.routeall()
    if err ~= nil then
        return nil, SelectError:new("Failed to get all replicasets: %s", err)
    end

    local space = utils.get_space(space_name, replicasets)
    if space == nil then
        return nil, SelectError:new("Space %s doesn't exists", space_name)
    end

    local space_format = space:format()

    local after_tuple = utils.flatten(opts.after, space_format)

    -- plan select
    local plan, err = select_plan.new(space, conditions, {
        limit = opts.limit,
        after_tuple = after_tuple,
    })

    if err ~= nil then
        return nil, SelectError:new("Failed to plan select: %s", err)
    end

    local key_parts = space.index[plan.scanner.index_id].parts

    -- XXX: this is the temporary solution
    -- The next step is to generate comparator based on plan
    local function gt_comparator(left, right)
        local key_def = key_def_lib.new(key_parts)
        return key_def:compare(left, right) < 0
    end

    local iter = Iterator.new({
        space_name = space_name,
        space_format = space_format,
        key_parts = key_parts,
        iteration_func = select_iteration,
        comparator = gt_comparator,

        conditions = conditions,
        after_tuple = after_tuple,
        limit = opts.limit,

        batch_size = opts.batch_size,
        replicasets = replicasets,

        timeout = opts.timeout,
    })

    return iter
end

return select_module
