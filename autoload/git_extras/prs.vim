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

" The name column is there only when the file names someone
function! s:line(pr, names) abort
  let l:state = a:pr.isDraft ? 'draft'
        \ : get(s:states, type(a:pr.reviewDecision) == v:t_string ? a:pr.reviewDecision : '', '-')
  let l:author = type(a:pr.author) == v:t_dict ? a:pr.author.login : 'ghost'
  let l:name = empty(a:names) ? '' : printf('%-20.20s ', get(a:names, tolower(l:author), ''))
  return printf('#%-5d %-8s %-4s %-16.16s %s%-30.30s %s', a:pr.number, l:state,
        \ git_extras#age(a:pr.updatedAt), l:author, l:name, a:pr.headRefName, a:pr.title)
endfunction

" Column headings, in s:line()'s widths
function! s:heading(names) abort
  let l:name = empty(a:names) ? '' : printf('%-20s ', 'name')
  return printf('%-6s %-8s %-4s %-16s %s%-30s %s', '#', 'state', 'age', 'author',
        \ l:name, 'branch', 'title')
endfunction

function! s:render() abort
  let l:out = git_extras#gh(b:git_extras_worktree, 'api graphql -F owner={owner} -F name={repo}'
        \ . ' -F count=' . b:git_extras_count . ' -f query=' . shellescape(s:query))
  if l:out is v:null
    return
  endif
  let l:prs = json_decode(l:out).data.repository.pullRequests.nodes
  let l:names = s:authors()
  setlocal modifiable
  silent %delete _
  call setline(1, ['Open PRs (' . len(l:prs) . ')  <CR> checkout  o browser  r refresh  q close',
        \ s:heading(l:names)] + map(copy(l:prs), 's:line(v:val, l:names)'))
  setlocal nomodifiable nomodified
  call git_extras#list_fit()
  call cursor(3, 1)
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
  nnoremap <buffer><silent> <CR> <Cmd>call <SID>checkout()<CR>
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

function! s:browse() abort
  let l:number = s:number()
  if l:number
    call git_extras#gh(b:git_extras_worktree, 'pr view --web ' . l:number)
  endif
endfunction
