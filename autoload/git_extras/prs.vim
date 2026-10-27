" :PRs: the repo's open pull requests, most recently updated first, in a
" window at the bottom. One GraphQL query through gh; JSON is parsed here, so
" jq isn't needed.

let s:query = 'query($owner: String!, $name: String!, $count: Int!) {'
      \ . ' repository(owner: $owner, name: $name) {'
      \ . ' pullRequests(states: OPEN, first: $count,'
      \ . ' orderBy: {field: UPDATED_AT, direction: DESC}) {'
      \ . ' nodes { number title isDraft headRefName updatedAt reviewDecision'
      \ . ' author { login } } } } }'

let s:states = {'APPROVED': 'approved', 'CHANGES_REQUESTED': 'changes',
      \ 'REVIEW_REQUIRED': 'review'}

function! s:error(msg) abort
  echohl ErrorMsg
  echomsg 'git-extras: ' . a:msg
  echohl None
endfunction

" login -> readable name, from g:git_extras_pr_authors (default
" ~/.config/gh-pr-authors.txt), one name:login per line; {} without the file.
" Keyed lowercase: logins aren't case-sensitive
function! s:authors() abort
  let l:file = expand(get(g:, 'git_extras_pr_authors', '~/.config/gh-pr-authors.txt'))
  let l:names = {}
  if filereadable(l:file)
    for l:line in readfile(l:file)
      let l:m = matchlist(l:line, '^\s*\([^:#[:space:]][^:]\{-}\)\s*:\s*\([^:[:space:]]\+\)\s*$')
      if !empty(l:m)
        let l:names[tolower(l:m[2])] = l:m[1]
      endif
    endfor
  endif
  return l:names
endfunction

" Who opened it: their name from the authors file, else the login
function! s:who(pr, names) abort
  let l:login = type(a:pr.author) == v:t_dict ? a:pr.author.login : 'ghost'
  return get(a:names, tolower(l:login), l:login)
endfunction

function! s:state(pr) abort
  return a:pr.isDraft ? 'draft'
        \ : get(s:states, type(a:pr.reviewDecision) == v:t_string ? a:pr.reviewDecision : '', '-')
endfunction

" Cut or padded to width screen cells: printf counts bytes, and names aren't
" all ASCII
function! s:pad(text, width) abort
  let l:text = a:text
  while strdisplaywidth(l:text) > a:width
    let l:text = strcharpart(l:text, 0, strchars(l:text) - 1)
  endwhile
  return l:text . repeat(' ', a:width - strdisplaywidth(l:text))
endfunction

" Who, title and branch are what you filter on, so they come first after the
" number; their widths fit the fetched PRs, so the columns stay put while
" filtering. Age is last: the order already tells it
function! s:format(widths, num, who, title, branch, state, age) abort
  return printf('%-6s %s  %s  %s  %-8s %s', a:num, s:pad(a:who, a:widths[0]),
        \ s:pad(a:title, a:widths[1]), s:pad(a:branch, a:widths[2]), a:state, a:age)
endfunction

function! s:line(pr, widths) abort
  return s:format(a:widths, '#' . a:pr.number, a:pr._who, a:pr.title,
        \ a:pr.headRefName, s:state(a:pr), git_extras#age(a:pr.updatedAt))
endfunction

" Fetches the PRs into b:git_extras_prs, then draws them through the filter
function! s:render() abort
  let l:out = git_extras#gh(b:git_extras_worktree, 'api graphql -F owner={owner} -F name={repo}'
        \ . ' -F count=' . b:git_extras_count . ' -f query=' . shellescape(s:query))
  if l:out is v:null
    return
  endif
  let l:prs = json_decode(l:out).data.repository.pullRequests.nodes
  let l:names = s:authors()
  for l:pr in l:prs
    let l:pr._who = s:who(l:pr, l:names)
  endfor
  let b:git_extras_prs = l:prs
  let b:git_extras_widths = [
        \ min([20, max([3] + map(copy(l:prs), 'strdisplaywidth(v:val._who)'))]),
        \ min([60, max([5] + map(copy(l:prs), 'strdisplaywidth(v:val.title)'))]),
        \ min([30, max([6] + map(copy(l:prs), 'strdisplaywidth(v:val.headRefName)'))])]
  call s:draw()
  call cursor(3, 1)
endfunction

" The fetched PRs that fuzzy-match b:git_extras_filter on who, title and branch, best
" first (as fzf: space-separated words each match); all of them, latest first,
" without a filter
function! s:filtered() abort
  if empty(b:git_extras_filter)
    return b:git_extras_prs
  endif
  return matchfuzzy(b:git_extras_prs, b:git_extras_filter,
        \ {'text_cb': {pr -> pr._who . ' ' . pr.title . ' ' . pr.headRefName}})
endfunction

function! s:draw() abort
  let l:prs = s:filtered()
  let l:count = empty(b:git_extras_filter) ? len(l:prs)
        \ : len(l:prs) . '/' . len(b:git_extras_prs) . ' matching ' . string(b:git_extras_filter)
  setlocal modifiable
  silent %delete _
  call setline(1, ['Open PRs (' . l:count . ')  <CR> checkout  / filter  t threads  o browser  r refresh  q close',
        \ s:format(b:git_extras_widths, '#', 'who', 'title', 'branch', 'state', 'age')]
        \ + map(copy(l:prs), 's:line(v:val, b:git_extras_widths)'))
  setlocal nomodifiable nomodified
  call git_extras#list_fit()
endfunction

" Filters as you type: <CR> keeps the filter (empty shows them all), <Esc>
" puts the previous one back; <BS>, <C-w> and <C-u> edit it
function! s:filter() abort
  let l:before = b:git_extras_filter
  while 1
    call s:draw()
    call cursor(3, 1)
    redraw
    echo '/' . b:git_extras_filter
    try
      let l:key = getchar()
    catch /^Vim:Interrupt$/
      let l:key = "\<Esc>"
    endtry
    let l:key = type(l:key) == v:t_number ? nr2char(l:key) : l:key
    if l:key ==# "\<CR>"
      break
    elseif l:key ==# "\<Esc>"
      let b:git_extras_filter = l:before
      call s:draw()
      call cursor(3, 1)
      break
    elseif l:key ==# "\<BS>" || l:key ==# "\<C-h>"
      let b:git_extras_filter = strcharpart(b:git_extras_filter, 0, strchars(b:git_extras_filter) - 1)
    elseif l:key ==# "\<C-w>"
      let b:git_extras_filter = substitute(b:git_extras_filter, '\S*\s*$', '', '')
    elseif l:key ==# "\<C-u>"
      let b:git_extras_filter = ''
    elseif l:key =~# '^\p$'
      let b:git_extras_filter .= l:key
    endif
  endwhile
  redraw
  echo ''
endfunction

function! git_extras#prs#open(count) abort
  let l:worktree = FugitiveWorkTree()
  if empty(l:worktree)
    call s:error('not in a git work tree')
    return
  endif
  if !git_extras#require_remote(':PRs')
    return
  endif
  call git_extras#list_open('git-extras://prs/' . fnamemodify(l:worktree, ':t'))
  let b:git_extras_worktree = l:worktree
  let b:git_extras_count = empty(a:count) ? 20 : a:count
  let b:git_extras_filter = ''
  nnoremap <buffer><silent> <CR> <Cmd>call <SID>checkout()<CR>
  nnoremap <buffer><silent> / <Cmd>call <SID>filter()<CR>
  nnoremap <buffer><silent> t <Cmd>call <SID>threads()<CR>
  nnoremap <buffer><silent> o <Cmd>call <SID>browse()<CR>
  nnoremap <buffer><silent> r <Cmd>call <SID>render()<CR>
  call s:render()
endfunction

function! s:number() abort
  return str2nr(matchstr(getline('.'), '^#\zs\d\+'))
endfunction

" gh pr checkout, then back to the buffer you came from, reloaded
function! s:checkout() abort
  let l:number = s:number()
  if !l:number
    return
  endif
  let l:worktree = b:git_extras_worktree
  if git_extras#gh(l:worktree, 'pr checkout ' . l:number) is v:null
    return
  endif
  call git_extras#list_close()
  checktime
  echo 'Checked out #' . l:number . ' (:BranchDiff, :BranchCommits to review)'
  call git_extras#comments#check()
endfunction

function! s:threads() abort
  let l:number = s:number()
  if l:number
    call git_extras#threads#open(l:number, b:git_extras_worktree)
  endif
endfunction

function! s:browse() abort
  let l:number = s:number()
  if l:number
    call git_extras#gh(b:git_extras_worktree, 'pr view --web ' . l:number)
  endif
endfunction
