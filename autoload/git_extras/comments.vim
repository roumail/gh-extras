" Review comments are vim-review's (:Comment, :Comments, :CommentsSave,
" :CommentsLoad). This is its provider for git work trees: comments are on
" files in the work tree or the branch side of a fugitive diff, paths are
" relative to the work tree, and saves are per branch in the git dir. Plus
" :CommentsSubmit, which posts them to the branch's PR.

function! s:error(msg) abort
  echohl ErrorMsg
  echomsg 'git-extras: ' . a:msg
  echohl None
endfunction

" The current buffer's path relative to the work tree: a file, or a
" fugitive:// object (a commit's or the index's version of one). {} outside
" a work tree, so vim-review's default applies.
function! s:target() abort
  if empty(FugitiveWorkTree())
    return {}
  endif
  let l:path = FugitivePath(@%, '')
  if empty(l:path) || l:path =~# '^/'
    return {'error': 'not a file in the git work tree'}
  endif
  if @% =~# '^fugitive://' && git_extras#is_base(FugitiveParse(@%)[0])
    return {'error': 'comment on the branch side of the diff, not the merge-base'}
  endif
  return {'path': l:path}
endfunction

" Saves for the current branch (the commit when detached), in the git dir
" shared by all work trees, so never committed:
" vim-review/<branch>/<time>.txt
function! s:save_dir() abort
  let l:common = FugitiveCommonDir()
  let l:head = FugitiveHead(7)
  return empty(l:common) || empty(l:head) ? ''
        \ : l:common . '/vim-review/' . l:head
endfunction

" Makes this vim-review's provider
function! git_extras#comments#init() abort
  call review#use({
        \ 'root': function('FugitiveWorkTree'),
        \ 'target': function('s:target'),
        \ 'save_dir': function('s:save_dir'),
        \ 'scope': function('FugitiveHead', [7]),
        \ })
endfunction

" Warns when the unsaved comments are from another branch than HEAD
function! git_extras#comments#check() abort
  if exists('g:loaded_review')
    call review#check()
  endif
endfunction

" The commit to review: head when it is one of the PR's, so the comments
" stay on it after newer pushes. GitHub rejects a commit the PR doesn't have
" (unpushed or rebased), so then the PR's head, if the commented files are
" the same there. '' (after an error) otherwise.
function! s:review_commit(cd, number, head, comments) abort
  let l:commits = systemlist(a:cd . 'gh api --paginate repos/{owner}/{repo}/pulls/'
        \ . a:number . '/commits --jq ".[].sha"')
  if v:shell_error || empty(l:commits)
    call s:error('gh: ' . substitute(join(l:commits, ' '), '\n', ' ', 'g'))
    return ''
  endif
  if index(l:commits, a:head) >= 0
    return a:head
  endif
  let l:tip = l:commits[-1]
  let l:paths = uniq(sort(map(copy(a:comments), 'v:val.path')))
  if FugitiveExecute(['cat-file', '-e', l:tip . '^{commit}']).exit_status
    let l:remotes = FugitiveExecute(['remote']).stdout
    let l:remote = index(l:remotes, 'origin') >= 0 ? 'origin' : get(l:remotes, 0, '')
    call FugitiveExecute(['fetch', l:remote, 'pull/' . a:number . '/head'])
  endif
  let l:diff = FugitiveExecute(['diff', '--name-only', l:tip, a:head, '--'] + l:paths)
  if l:diff.exit_status
    call s:error('git: cannot compare HEAD with the PR head ' . l:tip[:6])
    return ''
  endif
  call filter(l:diff.stdout, '!empty(v:val)')
  if !empty(l:diff.stdout)
    call s:error('HEAD ' . a:head[:6] . ' is not in PR ' . a:number . ', and its head '
          \ . l:tip[:6] . ' has these commented files different: '
          \ . join(l:diff.stdout, ', ') . '; push, or check out the PR')
    return ''
  endif
  return l:tip
endfunction

" The comments GitHub would reject, as path:line labels: their lines aren't
" in a hunk of the PR's diff at commit (merge-base with its base..commit, 3
" lines of context, as GitHub shows it), or a range spans two hunks. v:null
" (after an error) when that diff can't be read.
function! s:outside_diff(worktree, number, commit, comments) abort
  let l:base = git_extras#gh(a:worktree, 'api repos/{owner}/{repo}/pulls/'
        \ . a:number . ' --jq .base.sha')
  if l:base is v:null
    return v:null
  endif
  let l:base = trim(l:base)
  if FugitiveExecute(['cat-file', '-e', l:base . '^{commit}']).exit_status
    let l:remotes = FugitiveExecute(['remote']).stdout
    call FugitiveExecute(['fetch', index(l:remotes, 'origin') >= 0 ? 'origin'
          \ : get(l:remotes, 0, ''), l:base])
  endif
  let l:fork = FugitiveExecute(['merge-base', l:base, a:commit])
  let l:diff = l:fork.exit_status ? l:fork : FugitiveExecute(['diff', '-U3',
        \ '--no-color', '--no-ext-diff', l:fork.stdout[0], a:commit, '--']
        \ + uniq(sort(map(copy(a:comments), 'v:val.path'))))
  if l:diff.exit_status
    call s:error('git: cannot read the diff of PR ' . a:number . ' at ' . a:commit[:6])
    return v:null
  endif
  " {path: [[first, last], ...]}, the new side's lines of each hunk
  let l:hunks = {}
  let l:path = ''
  for l:line in l:diff.stdout
    if l:line =~# '^+++ '
      let l:path = l:line =~# '^+++ b/' ? l:line[6:] : ''
      let l:hunks[l:path] = []
    else
      let l:m = matchlist(l:line, '^@@ -\S\+ +\(\d\+\)\%(,\(\d\+\)\)\= @@')
      if !empty(l:m) && !empty(l:path)
        let l:first = str2nr(l:m[1])
        call add(l:hunks[l:path], [l:first, l:first + (empty(l:m[2]) ? 1 : str2nr(l:m[2])) - 1])
      endif
    endif
  endfor
  let l:outside = []
  for l:c in a:comments
    let l:start = get(l:c, 'start_line', l:c.line)
    if empty(filter(copy(get(l:hunks, l:c.path, [])),
          \ 'v:val[0] <= l:start && l:c.line <= v:val[1]'))
      call add(l:outside, l:c.path . ':' . (l:start == l:c.line ? '' : l:start . '-') . l:c.line)
    endif
  endfor
  return l:outside
endfunction

" Posts the comments as one pending review of HEAD on a PR (the current
" branch's, or number), so you can check them on GitHub and submit there or
" with gh.
function! git_extras#comments#submit(number) abort
  let l:worktree = FugitiveWorkTree()
  if empty(l:worktree)
    call s:error('not in a git work tree')
    return
  endif
  if !git_extras#require_remote(':CommentsSubmit')
    return
  endif
  call review#check()
  let l:comments = review#list()
  if empty(l:comments)
    call s:error('no review comments')
    return
  endif
  " Their lines were gone when loaded: they'd land on whatever is there now
  let l:orphaned = len(filter(copy(l:comments), 'get(v:val, "orphaned")'))
  if l:orphaned
    call s:error(l:orphaned . ' comments whose lines are gone (W in :Comments); comment again where they belong, or drop them, first')
    return
  endif
  " The review is of HEAD, the commit you read: GitHub rejects it when HEAD
  " isn't in the PR, and keeps the comments on it after newer pushes. Lines
  " are the work tree's, so a commented file must not have changed since.
  let l:head = FugitiveExecute(['rev-parse', 'HEAD'])
  let l:changed = FugitiveExecute(['diff', '--name-only', 'HEAD', '--']
        \ + uniq(sort(map(copy(l:comments), 'v:val.path'))))
  if l:head.exit_status || l:changed.exit_status
    call s:error('git: cannot read HEAD or its changes')
    return
  endif
  call filter(l:changed.stdout, '!empty(v:val)')
  if !empty(l:changed.stdout)
    call s:error('comments on files changed since HEAD, so their lines are not its: '
          \ . join(l:changed.stdout, ', ') . '; commit or stash the changes first')
    return
  endif
  for l:c in l:comments
    let l:c.side = 'RIGHT'
    if has_key(l:c, 'start_line')
      let l:c.start_side = 'RIGHT'
    endif
  endfor
  let l:cd = 'cd ' . shellescape(l:worktree) . ' && '
  let l:number = git_extras#pr_number(l:worktree, a:number)
  if empty(l:number)
    return
  endif
  let l:commit = s:review_commit(l:cd, l:number, l:head.stdout[0], l:comments)
  if empty(l:commit)
    return
  endif
  let l:outside = s:outside_diff(l:worktree, l:number, l:commit, l:comments)
  if l:outside is v:null
    return
  elseif !empty(l:outside)
    call s:error(len(l:outside) . ' comments on lines outside the PR''s diff, which GitHub rejects: '
          \ . join(l:outside, ', ') . '; move them into a changed hunk, or drop them (dd in :Comments)')
    return
  endif
  let l:out = system(l:cd . 'gh api repos/{owner}/{repo}/pulls/' . l:number
        \ . '/reviews --input - --jq .html_url',
        \ json_encode({'commit_id': l:commit, 'comments': l:comments}))
  if v:shell_error
    call s:error('gh: ' . substitute(trim(l:out), '\n', ' ', 'g'))
    return
  endif
  echo 'Pending review of ' . l:commit[:6] . ' with ' . len(l:comments)
        \ . ' comments: ' . trim(l:out)
endfunction
