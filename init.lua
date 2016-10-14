local ffi = require 'ffi'
local bit = require 'bit'

local luagit = {}

local function class(gitType)
  local Class = {}
  Class.__index = function(t, k)
    if Class[k] then
      return Class[k]
    elseif gitType ~= nil then
      local hasfn, gitfn  = pcall(function()
        return luagit.C['git_'..gitType..'_'..k]
      end)
      if hasfn then
        return function(t, ...)
          local isPtrPtr, handle = pcall(function() return t.handle[0] end)
          if not isPtrPtr then handle = t.handle end
          return gitfn(handle, ...)
        end
      end
    end
  end

  setmetatable(Class, {
    __call = function(cls, ...)
      local self = setmetatable({}, cls)
      self.type = gitType
      self:__init(...)
      return self
    end,
  })

  return Class
end

luagit.C = require 'luagit-ffi.ffi'
luagit.Repository = class('repository')
luagit.Index = class('index')
luagit.Tree = class('tree')
luagit.OID = class('oid') -- SHA
luagit.StatusList = class('status_list')
luagit.shutdown = function() luagit.C.git_libgit2_shutdown() end

function luagit.getLastError()
  local giterr = luagit.C.giterr_last()
  if giterr == nil then return nil end
  return {
    message = ffi.string(giterr.message),
    code = giterr.klass,
  }
end
-- luagit.errors = setmetatable({}, {
--   __index = function(k, v) return luagit.C['GIT_'..k] end
-- })

setmetatable(luagit, {
  __index = function(lg, key)
    return lg.C['git_'..key]
  end
})

function makeFlags(prefix, opts)
  opts = opts or {}
  local flags = 0
  for i,opt in pairs(opts) do
    flags = bit.bor(flags, luagit.C['GIT_'..prefix..'_'..opt])
  end
  return flags
end

function makeCheckoutOpts(opts)
  opts = opts or {}

  return ffi.new('git_checkout_options', {
    version = 1,
    checkout_strategy = makeFlags('CHECKOUT', opts.strategy),
    paths = opts.paths and makeStrArray(opts.paths) or nil,
  })
end

function luagit.Repository:__init(path)
  self.path = path

  self.handle = ffi.new('git_repository*[1]')
  luagit.repository_open(self.handle, path)
end

function luagit.Repository:getIndex()
  local index = luagit.Index()
  luagit.repository_index(index.handle, self.handle[0])
  index.repository = self
  return index
end

function luagit.Repository:getStatus(opts)
  local status = luagit.StatusList()
  local flags = makeFlags('STATUS_OPT', opts)
  local opts = ffi.new('git_status_options', {version=1, flags=flags})
  luagit.status_list_new(status.handle, self.handle[0], opts)
  return status
end

function makeSig(sigspec)
  return ffi.new('git_signature', {
    name=ffi.cast('char*', ffi.new('const char*', sigspec.name)),
    email=ffi.cast('char*', ffi.new('const char*', sigspec.email)),
    when=ffi.new('git_time', sigspec.when)
  })
end

function luagit.Repository:commit(updateRef, author, committer, msg, _tree, parents)
  parents = parents or {}

  local tree = _tree
  if tree.type ~= 'tree' then tree = self:lookupTree(tree) end

  author = makeSig(author)
  committer = makeSig(committer)

  local parentsArr
  if #parents > 0 then
    parentsArr = ffi.new('git_commit['..#parents..']', parents)
  end

  local oid = luagit.OID()
  luagit.commit_create(oid.handle, self.handle[0], updateRef, author, committer, nil, msg, tree.handle[0], #parents, parentsArr)

  if _tree.type ~= 'tree' then
    tree:free()
  end

  return oid
end

function luagit.Repository:lookupTree(oid)
  oid = luagit.OID(oid)
  local tree = luagit.Tree()
  local err = luagit.tree_lookup(tree.handle, self.handle[0], oid.handle)
  if err ~= 0 then error('Could not look up tree.') end
  tree.repository = self
  return tree
end

function luagit.Repository:stashSave(stasher, msg, opts)
  stasher = makeSig(stasher)
  local flags = makeFlags('STASH', opts)
  local oid = luagit.OID()
  local stashed = luagit.stash_save(oid.handle, self.handle[0], stasher, msg, flags)
  return stashed, oid
end

function luagit.Repository:stashPop(index, opts)
  opts = opts or {}
  local applyOpts = ffi.new('git_stash_apply_options', {
    version = 1,
    apply_flags = makeFlags('STASH_APPLY', opts.applyFlags),
    checkout_options = makeCheckoutOpts(opts.checkoutOpts),
  })
  return luagit.stash_pop(self.handle[0], index, applyOpts)
end

function luagit.Repository:checkout(ref, opts)
  -- this type of function should be autoconverted from the api
  opts = (type(ref) == 'table' and ref.type == nil) and ref or opts
  local coOpts = makeCheckoutOpts(opts)

  if ref.type == 'index' then
    return luagit.checkout_index(self.handle[0], ref.handle[0], coOpts)
  elseif ref.type == 'tree' or ref.type == 'commit' then
    local objHandle = ffi.cast('git_object*', ref.handle[0])
    return luagit.checkout_tree(self.handle[0], objHandle, coOpts)
  else
    return luagit.checkout_head(self.handle[0], coOpts)
  end
end

function luagit.Tree:__init()
  self.handle = ffi.new('git_tree*[1]')
end

function luagit.Index:__init()
  self.handle = ffi.new('git_index*[1]')
  luagit.index_new(self.handle)
end

function luagit.Index:addAll(pathspecs, opts, callback, payload)
  opts = opts or {}

  local ps = ffi.cast('char**', ffi.new('const char*['..#pathspecs..']', pathspecs))
  local psArr = ffi.new('git_strarray', {strings=ps, count=#pathspecs})
  local flags = makeFlags('INDEX_ADD', opts)

  return self:add_all(psArr, flags, callback, payload)
end

function luagit.Index:readTree(treeOrOid)
  assert(treeOrOid.type == 'tree' or self.repository ~= nil)

  local tree = treeOrOid
  if treeOrOid.type ~= 'tree' then
    tree = self.repository:lookupTree(treeOrOid)
  end

  luagit.index_read_tree(self.handle[0], tree.handle[0])

  if treeOrOid.type ~= 'tree' then tree:free() end

  return self
end

function luagit.Index:writeTree()
  local oid = luagit.OID()
  luagit.index_write_tree(oid.handle, self.handle[0])
  return oid
end

function luagit.Index:write()
  print(luagit.index_write(self.handle[0]))
end

function luagit.StatusList:__init()
  self.handle = ffi.new('git_status_list*[1]')
end

function luagit.OID:__init(existing)
  if type(existing) == 'table' then
    self.handle = existing.handle
  elseif type(existing) == 'cdata' then
    self.handle = existing
  elseif type(existing) == 'string' then
    self.handle = ffi.new('git_oid')
    self:fromstr(existing)
  else
    self.handle = ffi.new('git_oid')
  end
end

function luagit.OID:__tostring()
  local str = ffi.new('char[41]')
  luagit.oid_tostr(str, 41, self.handle)
  return ffi.string(str)
end

luagit.C.git_libgit2_init()

return luagit
