function! s:query(state, fields) abort
  return 'query($owner: String!, $name: String!, $count: Int!) {'
        \ . ' repository(owner: $owner, name: $name) {'
        \ . ' pullRequests(states: ' . a:state . ', first: $count,'
        \ . ' orderBy: {field: UPDATED_AT, direction: DESC}) {'
        \ . ' nodes { number title headRefName author { login } ' . a:fields . ' } } } }'
endfunction

let s:open_query = s:query('OPEN', 'isDraft updatedAt reviewDecision')
" GitHub can't order by merge time; updated time is close, and the fetched PRs
" are sorted by mergedAt
let s:merged_query = s:query('MERGED', 'mergedAt mergeCommit { oid }')

let s:states = {'APPROVED': 'approved', 'CHANGES_REQUESTED': 'changes',
      \ 'REVIEW_REQUIRED': 'review'}

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

function! s:fetch() abort
  let l:out = gh_extras#gh(b:gh_extras_worktree, 'api graphql -F owner={owner} -F name={repo}'
        \ . ' -F count=' . b:gh_extras_count
        \ . ' -f query=' . shellescape(b:gh_extras_merged ? s:merged_query : s:open_query))
  if l:out is v:null
    return v:null
  endif
  " Parsed here, so jq isn't needed
  let l:prs = json_decode(l:out).data.repository.pullRequests.nodes
  if b:gh_extras_merged
    call sort(l:prs, {a, b -> a.mergedAt <# b.mergedAt ? 1 : a.mergedAt ># b.mergedAt ? -1 : 0})
  endif
  " login -> readable name, from name:login lines; keyed lowercase: logins
  " aren't case-sensitive
  let l:names = {}
  let l:file = expand(get(g:, 'gh_extras_pr_authors', '~/.config/gh-pr-authors.txt'))
  for l:line in filereadable(l:file) ? readfile(l:file) : []
    let l:m = matchlist(l:line, '^\s*\([^:#[:space:]][^:]\{-}\)\s*:\s*\([^:[:space:]]\+\)\s*$')
    if !empty(l:m)
      let l:names[tolower(l:m[2])] = l:m[1]
    endif
  endfor
  for l:pr in l:prs
    let l:login = type(l:pr.author) == v:t_dict ? l:pr.author.login : 'ghost'
    let l:pr._who = get(l:names, tolower(l:login), l:login)
  endfor
  let b:gh_extras_widths = [
        \ min([20, max([3] + map(copy(l:prs), 'strdisplaywidth(v:val._who)'))]),
        \ min([60, max([5] + map(copy(l:prs), 'strdisplaywidth(v:val.title)'))]),
        \ min([30, max([6] + map(copy(l:prs), 'strdisplaywidth(v:val.headRefName)'))])]
  return l:prs
endfunction

function! s:heading(prs) abort
  let l:merged = b:gh_extras_merged
  return [(l:merged ? 'Merged' : 'Open') . ' PRs (' . len(a:prs) . ')',
        \ s:format(b:gh_extras_widths, '#', 'who', 'title', 'branch',
        \   l:merged ? 'commit' : 'state', l:merged ? 'merged' : 'age')]
endfunction

function! s:rows(prs) abort
  let l:merged = b:gh_extras_merged
  return map(copy(a:prs), {_, pr -> {'item': pr, 'lines': [s:format(b:gh_extras_widths,
        \ '#' . pr.number, pr._who, pr.title, pr.headRefName,
        \ l:merged ? s:merge_commit(pr)[:6] : pr.isDraft ? 'draft'
        \ : get(s:states, type(pr.reviewDecision) == v:t_string ? pr.reviewDecision : '', '-'),
        \ gh_extras#age(l:merged ? pr.mergedAt : pr.updatedAt))]}})
endfunction

function! s:merge_commit(pr) abort
  return type(a:pr.mergeCommit) == v:t_dict ? a:pr.mergeCommit.oid : ''
endfunction

" merged: the merged PRs (default 50), else the open ones (default 20)
function! gh_extras#prs#open(count, merged) abort
  let l:worktree = gh_extras#github_worktree(a:merged ? ':MergedPRs' : ':PRs')
  if empty(l:worktree)
    return
  endif
  call gh_extras#list#open('gh-extras://' . (a:merged ? 'merged-prs/' : 'prs/')
        \ . fnamemodify(l:worktree, ':t'), {
        \ 'fetch': function('s:fetch'), 'heading': function('s:heading'),
        \ 'rows': function('s:rows'), 'id': {pr -> pr.number},
        \ 'match': {pr -> pr._who . ' ' . pr.title . ' ' . pr.headRefName},
        \ 'keys': [
        \   {'key': '<CR>', 'hint': a:merged ? 'commit' : 'checkout', 'call': function('s:enter')},
        \   {'key': 't', 'hint': 'threads', 'call': function('s:threads')},
        \   {'key': 'o', 'hint': 'browser', 'call': function('s:browse')}]}, {
        \ 'gh_extras_worktree': l:worktree,
        \ 'gh_extras_gitdir': FugitiveGitDir(),
        \ 'gh_extras_merged': a:merged,
        "\ GitHub returns at most 100 at a time
        \ 'gh_extras_count': min([100, empty(a:count) ? (a:merged ? 50 : 20) : str2nr(a:count)]),
        \ })
endfunction

function! s:number() abort
  return get(gh_extras#list#item(), 'number', 0)
endfunction

function! s:enter() abort
  if b:gh_extras_merged
    call s:show_commit()
  else
    call s:checkout()
  endif
endfunction

" The merge commit (or squash commit) in fugitive, in the window above
function! s:show_commit() abort
  let l:pr = gh_extras#list#item()
  if empty(l:pr)
    return
  endif
  let l:number = l:pr.number
  let l:oid = s:merge_commit(l:pr)
  if empty(l:oid)
    call gh_extras#error('#' . l:number . ' has no merge commit')
    return
  endif
  call system('git -C ' . shellescape(b:gh_extras_worktree) . ' cat-file -e ' . l:oid . '^{commit}')
  if v:shell_error
    call gh_extras#error('commit ' . l:oid[:6] . ' is not here; :Git fetch first')
    return
  endif
  let l:file = FugitiveFind(l:oid, b:gh_extras_gitdir)
  if winnr('$') == 1
    aboveleft split
  else
    wincmd p
  endif
  execute 'edit' fnameescape(l:file)
endfunction

function! s:checkout() abort
  let l:number = s:number()
  if !l:number
    return
  endif
  let l:worktree = b:gh_extras_worktree
  if gh_extras#gh(l:worktree, 'pr checkout ' . l:number) is v:null
    return
  endif
  call gh_extras#list#close()
  checktime
  echo 'Checked out #' . l:number . ' (:BranchDiff, :BranchCommits to review)'
  if exists('g:loaded_fugitive_extras')
    call fugitive_extras#comments#check()
  endif
endfunction

function! s:threads() abort
  let l:number = s:number()
  if l:number
    call gh_extras#threads#open(l:number, b:gh_extras_worktree)
  endif
endfunction

function! s:browse() abort
  let l:number = s:number()
  if l:number
    call gh_extras#gh(b:gh_extras_worktree, 'pr view --web ' . l:number)
  endif
endfunction
