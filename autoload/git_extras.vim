function! s:git(args) abort
  let l:result = FugitiveExecute(a:args)
  if l:result.exit_status != 0
    return v:null
  endif
  return filter(copy(l:result.stdout), '!empty(v:val)')
endfunction

function! git_extras#error(msg) abort
  echohl ErrorMsg
  echomsg 'git-extras: ' . a:msg
  echohl None
endfunction

function! git_extras#gh(worktree, args, ...) abort
  let l:out = call('system', ['cd ' . shellescape(a:worktree) . ' && gh ' . a:args] + a:000)
  if v:shell_error
    call git_extras#error('gh: ' . substitute(trim(l:out), '\n', ' ', 'g'))
    return v:null
  endif
  return l:out
endfunction

function! git_extras#pr_number(worktree, number) abort
  if !empty(a:number)
    return a:number
  endif
  let l:number = trim(system('cd ' . shellescape(a:worktree)
        \ . ' && gh pr view --json number --jq .number'))
  if v:shell_error
    call git_extras#error('no PR for this branch; pass its number')
    return ''
  endif
  return l:number
endfunction

function! git_extras#age(iso) abort
  let l:p = matchlist(a:iso, '\v(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z')
  let l:epoch = 0
  if !empty(l:p)
    let [l:y, l:m, l:d] = [str2nr(l:p[1]), str2nr(l:p[2]), str2nr(l:p[3])]
    " Days from civil (Howard Hinnant's algorithm)
    let l:y -= l:m <= 2
    let l:era = l:y / 400
    let l:yoe = l:y - l:era * 400
    let l:epoch = (l:era * 146097 + l:yoe * 365 + l:yoe / 4 - l:yoe / 100
          \ + (153 * ((l:m + 9) % 12) + 2) / 5 + l:d - 1 - 719468) * 86400
          \ + str2nr(l:p[4]) * 3600 + str2nr(l:p[5]) * 60 + str2nr(l:p[6])
  endif
  let l:hours = (localtime() - l:epoch) / 3600
  return l:hours < 24 ? l:hours . 'h'
        \ : l:hours < 24 * 60 ? (l:hours / 24) . 'd'
        \ : (l:hours / 24 / 30) . 'mo'
endfunction

function! git_extras#github_worktree(command) abort
  let l:worktree = FugitiveWorkTree()
  if empty(l:worktree)
    call git_extras#error('not in a git work tree')
    return ''
  endif
  " gh finds the GitHub repo from the git remotes; without one it fails with
  " 'error parsing "owner" value'
  if empty(s:git(['remote']))
    call git_extras#error(a:command . ' needs the repo on GitHub, and it has no git remote')
    return ''
  endif
  return l:worktree
endfunction

function! git_extras#main_ref() abort
  " The remote ref first: the local branch is often stale after a fetch or a
  " `gh pr checkout`
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

function! s:base(branch) abort
  if empty(FugitiveGitDir())
    call git_extras#error('not in a git repository')
    return ''
  endif
  let l:branch = empty(a:branch) ? 'HEAD' : a:branch
  if !s:is_commit(l:branch)
    call git_extras#error('unknown branch ' . l:branch . ' (:Git fetch?)')
    return ''
  endif
  let l:main = git_extras#main_ref()
  if empty(l:main)
    call git_extras#error('no origin/HEAD, main or master found')
    return ''
  endif
  let l:base = s:git(['merge-base', l:branch, l:main])
  if empty(l:base)
    call git_extras#error('no merge-base between ' . l:branch . ' and ' . l:main)
    return ''
  endif
  let s:bases[l:base[0]] = 1
  return l:base[0]
endfunction

" Merge-bases these commands have diffed against, to tell a diff's base side
let s:bases = {}

function! git_extras#is_base(rev) abort
  return has_key(s:bases, matchstr(a:rev, '^\x\{40,}'))
endfunction

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

function! git_extras#branch_diff(branch) abort
  let l:base = s:base(a:branch)
  if !empty(l:base)
    call git_extras#compares#open(FugitiveGitDir(),
          \ empty(a:branch) ? FugitiveHead(7) : a:branch, l:base, a:branch)
  endif
endfunction

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

function! git_extras#complete_commits(lead, cmdline, pos) abort
  if strpart(a:cmdline, 0, a:pos) =~# '^\S\+\s\+\S*$'
    return git_extras#complete_branch(a:lead, a:cmdline, a:pos)
  endif
  return getcompletion(a:lead, 'file')
endfunction

function! git_extras#list_open(name) abort
  " A window of its own, so q and :q close only the list, never a window of yours
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

function! git_extras#list_close() abort
  if winnr('$') > 1
    close
  else
    enew
  endif
endfunction

function! git_extras#diff_close(name) abort
  if !empty(a:name) || has_key(t:, 'git_extras_compare')
    call git_extras#compares#close(a:name)
    return
  endif
  for l:win in reverse(range(1, winnr('$')))
    if bufname(winbufnr(l:win)) =~# '^fugitive://' && winnr('$') > 1
      execute l:win . 'close'
    endif
  endfor
  diffoff!
endfunction
