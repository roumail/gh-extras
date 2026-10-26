" Runs git in the current buffer's repo; returns stdout lines, or v:null on
" failure.
function! s:git(args) abort
  let l:result = FugitiveExecute(a:args)
  if l:result.exit_status != 0
    return v:null
  endif
  return filter(copy(l:result.stdout), '!empty(v:val)')
endfunction

function! s:error(msg) abort
  echohl ErrorMsg
  echomsg 'git-extras: ' . a:msg
  echohl None
endfunction

" gh finds the GitHub repo from the git remotes; without one it fails with
" 'error parsing "owner" value'. Errors and returns 0 when there is none.
function! git_extras#require_remote(command) abort
  if empty(s:git(['remote']))
    call s:error(a:command . ' needs the repo on GitHub, and it has no git remote')
    return 0
  endif
  return 1
endfunction

" The default branch as a ref: origin/HEAD, else main or master. The remote
" ref is preferred, since the local branch is often stale after a fetch or a
" `gh pr checkout`.
function! git_extras#main_ref() abort
  let l:head = s:git(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD'])
  if !empty(l:head)
    return l:head[0]
  endif
  for l:ref in ['refs/remotes/origin/main', 'refs/remotes/origin/master',
        \ 'refs/heads/main', 'refs/heads/master']
    if s:git(['show-ref', '--verify', '--quiet', l:ref]) isnot v:null
      return substitute(l:ref, '^refs/\%(remotes\|heads\)/', '', '')
    endif
  endfor
  return ''
endfunction

" The commit where branch (HEAD if empty) forked from main, so diffs show
" only that branch's changes (like a PR), not what landed on main since.
function! s:base(branch) abort
  if empty(FugitiveGitDir())
    call s:error('not in a git repository')
    return ''
  endif
  let l:branch = empty(a:branch) ? 'HEAD' : a:branch
  if !s:is_commit(l:branch)
    call s:error('unknown branch ' . l:branch . ' (:Git fetch?)')
    return ''
  endif
  let l:main = git_extras#main_ref()
  if empty(l:main)
    call s:error('no origin/HEAD, main or master found')
    return ''
  endif
  let l:base = s:git(['merge-base', l:branch, l:main])
  if empty(l:base)
    call s:error('no merge-base between ' . l:branch . ' and ' . l:main)
    return ''
  endif
  let s:bases[l:base[0]] = 1
  return l:base[0]
endfunction

" Merge-bases these commands have diffed against, to tell a diff's base side
let s:bases = {}

" Whether a fugitive revision ('<commit>:<path>') is a merge-base we diffed
" against
function! git_extras#is_base(rev) abort
  return has_key(s:bases, matchstr(a:rev, '^\x\{40,}'))
endfunction

" Index | working tree; with bang, the merge-base with main | working tree
function! git_extras#diff_this(bang) abort
  if !a:bang
    Gvdiffsplit
    return
  endif
  let l:base = s:base('')
  if !empty(l:base)
    execute 'Gvdiffsplit' l:base
  endif
endfunction

function! s:is_commit(rev) abort
  return s:git(['rev-parse', '--verify', '--quiet', a:rev . '^{commit}']) isnot v:null
endfunction

" With a branch, diffs are merge-base..branch; without, merge-base against the
" working tree, so uncommitted changes show too. Listed in :Compares as the
" branch, or the current branch's name.
function! git_extras#branch_diff(branch) abort
  let l:base = s:base(a:branch)
  if !empty(l:base)
    call git_extras#compares#open(FugitiveGitDir(),
          \ empty(a:branch) ? FugitiveHead(7) : a:branch, l:base, a:branch)
  endif
endfunction

" A first arg that names a commit is the branch; the rest go to git log.
function! git_extras#branch_commits(args) abort
  let l:first = matchstr(a:args, '^\S\+')
  let l:branch = 'HEAD'
  let l:rest = a:args
  if !empty(l:first) && l:first !~# '^-' && s:is_commit(l:first)
    let l:branch = l:first
    let l:rest = substitute(a:args, '^\S\+\s*', '', '')
  endif
  let l:base = s:base(l:branch)
  if !empty(l:base)
    execute 'Git log --oneline --decorate' l:base . '..' . l:branch l:rest
  endif
endfunction

function! git_extras#complete_branch(lead, cmdline, pos) abort
  let l:refs = s:git(['for-each-ref', '--sort=-committerdate',
        \ '--format=%(refname)', 'refs/heads', 'refs/remotes'])
  if l:refs is v:null
    return []
  endif
  " Skip origin/HEAD, an alias of the default branch
  call filter(l:refs, 'v:val !~# "^refs/remotes/[^/]\\+/HEAD$"')
  call map(l:refs, 'substitute(v:val, "^refs/\\%(heads\\|remotes\\)/", "", "")')
  return filter(l:refs, 'stridx(v:val, a:lead) == 0')
endfunction

" Branch for the first argument, files after it
function! git_extras#complete_commits(lead, cmdline, pos) abort
  if strpart(a:cmdline, 0, a:pos) =~# '^\S\+\s\+\S*$'
    return git_extras#complete_branch(a:lead, a:cmdline, a:pos)
  endif
  return getcompletion(a:lead, 'file')
endfunction

" The lists (:PRs, :Compares) are scratch buffers in a window of their own at
" the bottom, so q and :q close only them, never a window of yours.
function! git_extras#list_open(name) abort
  let l:winnr = bufwinnr('^' . a:name . '$')
  if l:winnr > 0
    execute l:winnr . 'wincmd w'
  else
    execute 'silent botright split' fnameescape(a:name)
  endif
  setlocal buftype=nofile bufhidden=wipe noswapfile nowrap nobuflisted winfixheight
  nnoremap <buffer><silent> q <Cmd>call git_extras#list_close()<CR>
endfunction

function! git_extras#list_fit() abort
  execute 'resize' min([line('$'), 15])
endfunction

" Closes its window, and with it the list (bufhidden=wipe); when it's the
" last window left, shows an empty buffer instead
function! git_extras#list_close() abort
  if winnr('$') > 1
    close
  else
    enew
  endif
endfunction

function! git_extras#diff_close() abort
  for l:win in reverse(range(1, winnr('$')))
    if bufname(winbufnr(l:win)) =~# '^fugitive://' && winnr('$') > 1
      execute l:win . 'close'
    endif
  endfor
  diffoff!
endfunction
