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
  if empty(filter(FugitiveExecute(['remote']).stdout, '!empty(v:val)'))
    call git_extras#error(a:command . ' needs the repo on GitHub, and it has no git remote')
    return ''
  endif
  return l:worktree
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
