function! s:fetch_missing(commit, ref) abort
  if FugitiveExecute(['cat-file', '-e', a:commit . '^{commit}']).exit_status
    let l:remotes = FugitiveExecute(['remote']).stdout
    call FugitiveExecute(['fetch', index(l:remotes, 'origin') >= 0 ? 'origin' : get(l:remotes, 0, ''), a:ref])
  endif
endfunction

function! s:target() abort
  if empty(FugitiveWorkTree())
    " vim-review's default applies
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

function! s:save_dir() abort
  " In the git dir shared by all work trees, so saves are never committed
  let l:common = FugitiveCommonDir()
  let l:head = FugitiveHead(7)
  return empty(l:common) || empty(l:head) ? ''
        \ : l:common . '/vim-review/' . l:head
endfunction

function! git_extras#comments#init() abort
  call review#use({
        \ 'root': function('FugitiveWorkTree'),
        \ 'target': function('s:target'),
        \ 'save_dir': function('s:save_dir'),
        \ 'scope': function('FugitiveHead', [7]),
        \ })
endfunction

function! git_extras#comments#check() abort
  if exists('g:loaded_review')
    call review#check()
  endif
endfunction

function! git_extras#comments#submit(number) abort
  let l:worktree = git_extras#github_worktree(':CommentsSubmit')
  if empty(l:worktree)
    return
  endif
  call review#check()
  let l:comments = review#list()
  if empty(l:comments)
    call git_extras#error('no review comments')
    return
  endif
  " Their lines were gone when loaded: they'd land on whatever is there now
  let l:orphaned = len(filter(copy(l:comments), 'get(v:val, "orphaned")'))
  if l:orphaned
    call git_extras#error(l:orphaned . ' comments whose lines are gone (W in :Comments); comment again where they belong, or drop them, first')
    return
  endif
  " The review is of HEAD, the commit you read: GitHub rejects it when HEAD
  " isn't in the PR, and keeps the comments on it after newer pushes. Lines
  " are the work tree's, so a commented file must not have changed since.
  let l:paths = uniq(sort(map(copy(l:comments), 'v:val.path')))
  let l:head = FugitiveExecute(['rev-parse', 'HEAD'])
  let l:changed = FugitiveExecute(['diff', '--name-only', 'HEAD', '--'] + l:paths)
  if l:head.exit_status || l:changed.exit_status
    call git_extras#error('git: cannot read HEAD or its changes')
    return
  endif
  call filter(l:changed.stdout, '!empty(v:val)')
  if !empty(l:changed.stdout)
    call git_extras#error('comments on files changed since HEAD, so their lines are not its: '
          \ . join(l:changed.stdout, ', ') . '; commit or stash the changes first')
    return
  endif
  let l:cd = 'cd ' . shellescape(l:worktree) . ' && '
  let l:number = git_extras#pr_number(l:worktree, a:number)
  if empty(l:number)
    return
  endif

  " The commit to review: HEAD when it is one of the PR's, so the comments stay
  " on it after newer pushes. GitHub rejects a commit the PR doesn't have
  " (unpushed or rebased), so then the PR's head, if the commented files are
  " the same there.
  let l:commits = systemlist(l:cd . 'gh api --paginate repos/{owner}/{repo}/pulls/'
        \ . l:number . '/commits --jq ".[].sha"')
  if v:shell_error || empty(l:commits)
    call git_extras#error('gh: ' . substitute(join(l:commits, ' '), '\n', ' ', 'g'))
    return
  endif
  let l:commit = l:head.stdout[0]
  if index(l:commits, l:commit) < 0
    let l:commit = l:commits[-1]
    call s:fetch_missing(l:commit, 'pull/' . l:number . '/head')
    let l:diff = FugitiveExecute(['diff', '--name-only', l:commit, l:head.stdout[0], '--'] + l:paths)
    if l:diff.exit_status
      call git_extras#error('git: cannot compare HEAD with the PR head ' . l:commit[:6])
      return
    endif
    call filter(l:diff.stdout, '!empty(v:val)')
    if !empty(l:diff.stdout)
      call git_extras#error('HEAD ' . l:head.stdout[0][:6] . ' is not in PR ' . l:number
            \ . ', and its head ' . l:commit[:6] . ' has these commented files different: '
            \ . join(l:diff.stdout, ', ') . '; push, or check out the PR')
      return
    endif
  endif

  " GitHub rejects a comment whose lines aren't in a hunk of the PR's diff at
  " the commit (merge-base with its base..commit, 3 lines of context, as
  " GitHub shows it), or whose range spans two hunks
  let l:base = git_extras#gh(l:worktree, 'api repos/{owner}/{repo}/pulls/'
        \ . l:number . ' --jq .base.sha')
  if l:base is v:null
    return
  endif
  let l:base = trim(l:base)
  call s:fetch_missing(l:base, l:base)
  let l:fork = FugitiveExecute(['merge-base', l:base, l:commit])
  let l:diff = l:fork.exit_status ? l:fork : FugitiveExecute(['diff', '-U3',
        \ '--no-color', '--no-ext-diff', l:fork.stdout[0], l:commit, '--'] + l:paths)
  if l:diff.exit_status
    call git_extras#error('git: cannot read the diff of PR ' . l:number . ' at ' . l:commit[:6])
    return
  endif
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
  for l:c in l:comments
    if empty(filter(copy(get(l:hunks, l:c.path, [])),
          \ 'v:val[0] <= l:c.start && l:c.end <= v:val[1]'))
      call add(l:outside, l:c.path . ':' . l:c.start . (l:c.end > l:c.start ? '-' . l:c.end : ''))
    endif
  endfor
  if !empty(l:outside)
    call git_extras#error(len(l:outside) . ' comments on lines outside the PR''s diff, which GitHub rejects: '
          \ . join(l:outside, ', ') . '; move them into a changed hunk, or drop them (dd in :Comments)')
    return
  endif
  let l:out = system(l:cd . 'gh api repos/{owner}/{repo}/pulls/' . l:number
        \ . '/reviews --input - --jq .html_url',
        \ json_encode({'commit_id': l:commit, 'comments': map(copy(l:comments),
        \   {_, c -> extend({'path': c.path, 'body': c.body, 'line': c.end, 'side': 'RIGHT'},
        \     c.end > c.start ? {'start_line': c.start, 'start_side': 'RIGHT'} : {})})}))
  if v:shell_error
    call git_extras#error('gh: ' . substitute(trim(l:out), '\n', ' ', 'g'))
    return
  endif
  echo 'Pending review of ' . l:commit[:6] . ' with ' . len(l:comments)
        \ . ' comments: ' . trim(l:out)
endfunction
