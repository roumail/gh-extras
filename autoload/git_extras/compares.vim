" dir is the git dir, so each work tree has its own comparisons
let s:compares = []

function! s:key(compare) abort
  return {'dir': a:compare.dir, 'name': a:compare.name}
endfunction

function! s:tabs(compare) abort
  return map(filter(gettabinfo(),
        \ {_, t -> get(t.variables, 'git_extras_compare', {}) == s:key(a:compare)}), 'v:val.tabnr')
endfunction

function! git_extras#compares#open(dir, name, base, head) abort
  let l:here = tabpagenr()
  let l:win = win_getid()
  let l:before = tabpagenr('$')
  " :Git in that repo, whichever buffer this is
  execute fugitive#Command(line('.'), -1, 0, 0, '', 'difftool -y ' . a:base . ' ' . a:head, a:dir)
  let l:files = tabpagenr('$') - l:before
  if !l:files
    echo 'git-extras: no changes in ' . a:name
    return
  endif
  let l:old = filter(copy(s:compares),
        \ 'v:val.dir ==# a:dir && v:val.name ==# a:name')
  if !empty(l:old) && l:old[0].base ==# a:base && l:old[0].head ==# a:head
    " The same diff again: its tabs still open stay in it
    call remove(s:compares, index(s:compares, l:old[0]))
  else
    call git_extras#compares#remove(a:dir, a:name)
  endif
  let l:compare = {'dir': a:dir, 'name': a:name, 'base': a:base,
        \ 'head': a:head, 'files': l:files, 'time': localtime(), 'win': l:win}
  call add(s:compares, l:compare)
  for l:tab in range(l:here + 1, l:here + l:files)
    call settabvar(l:tab, 'git_extras_compare', s:key(l:compare))
  endfor
endfunction

function! git_extras#compares#list(...) abort
  let l:dir = a:0 ? a:1 : FugitiveGitDir()
  let l:list = []
  for l:compare in reverse(filter(copy(s:compares), 'v:val.dir ==# l:dir'))
    call add(l:list, extend(copy(l:compare), {'tabs': s:tabs(l:compare)}))
  endfor
  return l:list
endfunction

function! git_extras#compares#remove(dir, name) abort
  for l:compare in filter(copy(s:compares),
        \ 'v:val.dir ==# a:dir && v:val.name ==# a:name')
    for l:tab in s:tabs(l:compare)
      call remove(gettabvar(l:tab, ''), 'git_extras_compare')
    endfor
    call remove(s:compares, index(s:compares, l:compare))
  endfor
endfunction

function! git_extras#compares#close(name) abort
  let l:key = empty(a:name) ? get(t:, 'git_extras_compare', {})
        \ : {'dir': FugitiveGitDir(), 'name': a:name}
  let l:compare = get(filter(copy(s:compares), 's:key(v:val) ==# l:key'), 0, {})
  if empty(l:compare)
    call git_extras#error('no comparison ' . get(l:key, 'name', '') . ' in :Compares')
    return
  endif
  let l:tabs = s:tabs(l:compare)
  if empty(l:tabs)
    echo 'git-extras: no tabs of ' . a:name . ' open'
    return
  endif
  let l:from = index(l:tabs, tabpagenr()) >= 0
  if len(l:tabs) == tabpagenr('$')
    " Vim keeps one tab: an empty one
    $tabnew
  endif
  let l:left = 0
  for l:tab in reverse(l:tabs)
    try
      execute l:tab . 'tabclose'
    catch
      " A file changed and not written
      let l:left += 1
    endtry
  endfor
  if l:from
    call win_gotoid(l:compare.win)
  endif
  if l:left
    call git_extras#error(l:left . ' tab(s) of ' . l:compare.name
          \ . ' left open: unsaved changes')
  endif
endfunction

function! git_extras#compares#complete(lead, cmdline, pos) abort
  return filter(map(git_extras#compares#list(), 'v:val.name'),
        \ 'stridx(v:val, a:lead) == 0')
endfunction


function! s:render() abort
  let b:git_extras_compares = git_extras#compares#list(b:git_extras_dir)
  let l:lines = ['Comparisons (' . len(b:git_extras_compares) . ')  <CR> open  d remove  r refresh  q close']
  for l:c in b:git_extras_compares
    let l:seconds = localtime() - l:c.time
    call add(l:lines, printf('%-30.30s %s..%-24.24s %3d files %3d open  %s', l:c.name,
          \ l:c.base[:6], empty(l:c.head) ? 'work tree' : l:c.head, l:c.files, len(l:c.tabs),
          \ l:seconds < 60 ? l:seconds . 's'
          \ : l:seconds < 3600 ? (l:seconds / 60) . 'm'
          \ : (l:seconds / 3600) . 'h'))
  endfor
  setlocal modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable nomodified
  call git_extras#list_fit()
  call cursor(2, 1)
endfunction

function! git_extras#compares#show() abort
  let l:dir = FugitiveGitDir()
  let l:worktree = FugitiveWorkTree()
  if empty(l:worktree)
    call git_extras#error('not in a git work tree')
    return
  endif
  call git_extras#list_open('git-extras://compares/' . fnamemodify(l:worktree, ':t'))
  let b:git_extras_dir = l:dir
  nnoremap <buffer><silent> <CR> <Cmd>call <SID>open()<CR>
  nnoremap <buffer><silent> d <Cmd>call <SID>remove()<CR>
  nnoremap <buffer><silent> r <Cmd>call <SID>render()<CR>
  call s:render()
endfunction

function! s:selected() abort
  return get(b:git_extras_compares, line('.') - 2, {})
endfunction

function! s:open() abort
  let l:compare = s:selected()
  if empty(l:compare)
    return
  endif
  let l:dir = b:git_extras_dir
  call git_extras#list_close()
  call git_extras#compares#open(l:dir, l:compare.name, l:compare.base, l:compare.head)
endfunction

function! s:remove() abort
  let l:compare = s:selected()
  if !empty(l:compare)
    call git_extras#compares#remove(b:git_extras_dir, l:compare.name)
    call s:render()
  endif
endfunction
