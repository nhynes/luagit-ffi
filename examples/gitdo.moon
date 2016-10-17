[==[
git = dofile('gitdo.moon')

gitState = tostring(git\saveState!)\sub(1, 8)
torch.save(gitState..'.t7', model)

-- years pass...

git.pushState(gitState)
torch.load(gitState..'.t7')
git.popState!
]==]

luagit = require 'luagit-ffi'

saveState = ->
  repo = luagit.Repository('.')
  index = with repo\getIndex!
    \addAll{'*'}

  stateTreeId = index\writeTree!

  index\free!
  repo\free!

  stateTreeId

pushStashed = false

pushState = (state) ->
  repo = luagit.Repository('.')

  emptySig = name: '', email: '', when: os.time!
  stashed, stash = repo\stashSave emptySig, state, {'KEEP_INDEX', 'INCLUDE_UNTRACKED'}
  pushStashed = stashed == 0

  stateTree = repo\lookupTree(state)
  repo\checkout(stateTree, {strategy: {'SAFE', 'USE_OURS'}})
    -- use_ours lets staged files overwrite those in the saved tree
    -- notice the KEEP_INDEX during the stash

  stateTree\free!
  repo\free!

popState = ->
  repo = luagit.Repository('.')

  repo\checkout strategy: {'FORCE'}
  if pushStashed
    pushStashed = nil
    repo\stashPop 0,
      applyFlags: {'REINSTATE_INDEX'},
      checkoutOpts: {strategy: {'FORCE'}}

  repo\free!

{:saveState, :pushState, :popState}
