" :Thread: a PR's review threads with their conversations, in a window at the
" bottom, to read the replies to your comments, answer them and resolve them
" without the GitHub UI. Replies post at once, as GitHub's Reply does.
" :Threads: the same, for the threads you're in across the open PRs.

" Comments are capped lower across PRs, to stay under GitHub's limit of
" 500,000 nodes a query
let s:pr_fields = 'number title headRefName headRefOid author { login }'
      \ . ' reviewThreads(first: 100) { nodes {'
      \ . ' id isResolved isOutdated path line startLine originalLine originalStartLine'
      \ . ' comments(first: %d) { nodes {'
      \ . ' author { login } body createdAt state originalCommit { oid } } } } }'

let s:one = 'query($owner: String!, $name: String!, $number: Int!) {'
      \ . ' viewer { login }'
      \ . ' repository(owner: $owner, name: $name) { pullRequest(number: $number) {'
      \ . printf(s:pr_fields, 100) . ' } } }'

let s:all = 'query($owner: String!, $name: String!) {'
      \ . ' viewer { login }'
      \ . ' repository(owner: $owner, name: $name) { pullRequests(states: OPEN, first: 50,'
      \ . ' orderBy: {field: UPDATED_AT, direction: DESC}) { nodes {'
      \ . printf(s:pr_fields, 50) . ' } } } }'

let s:reply = 'mutation($thread: ID!, $body: String!) {'
      \ . ' addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $thread, body: $body}) {'
      \ . ' comment { id state } } }'

let s:edit = 'mutation($comment: ID!, $body: String!) {'
      \ . ' updatePullRequestReviewComment(input: {pullRequestReviewCommentId: $comment, body: $body}) {'
      \ . ' pullRequestReviewComment { state } } }'

let s:resolve = 'mutation($thread: ID!) {'
      \ . ' %s(input: {threadId: $thread}) { thread { isResolved } } }'

function! s:error(msg) abort
  echohl ErrorMsg
  echomsg 'git-extras: ' . a:msg
  echohl None
endfunction

function! s:graphql(worktree, query, variables) abort
  let l:out = git_extras#gh(a:worktree, 'api graphql --input -',
        \ json_encode({'query': a:query, 'variables': a:variables}))
  return l:out is v:null ? v:null : json_decode(l:out)
endfunction

function! s:login(author) abort
  return type(a:author) == v:t_dict ? a:author.login : 'ghost'
endfunction

function! s:outdated(thread) abort
  return a:thread.isOutdated || a:thread.line is v:null
endfunction

" Where the thread is: on the PR's head (the work tree when that is the branch
" checked out), or, once its lines have changed (outdated), on the commit it
" was made on. line is null for a comment on the whole file.
function! s:place(thread) abort
  let l:outdated = s:outdated(a:thread)
  let l:line = l:outdated ? a:thread.originalLine : a:thread.line
  let l:start = l:outdated ? a:thread.originalStartLine : a:thread.startLine
  return {
        \ 'commit': l:outdated ? a:thread.comments.nodes[0].originalCommit.oid : a:thread.head,
        \ 'line': l:line is v:null ? 1 : l:line,
        \ 'range': l:line is v:null ? '' : (l:start is v:null ? '' : l:start . '-') . l:line,
        \ }
endfunction

" Open, and the last word isn't yours
function! s:waiting(thread, me) abort
  return !a:thread.isResolved
        \ && s:login(a:thread.comments.nodes[-1].author) !=? a:me
endfunction

" On your PR, or you wrote in it
function! s:mine(thread, pr, me) abort
  return s:login(a:pr.author) ==? a:me
        \ || !empty(filter(copy(a:thread.comments.nodes), 's:login(v:val.author) ==? a:me'))
endfunction

function! s:lines(thread, me) abort
  let l:place = s:place(a:thread)
  let l:state = a:thread.isResolved ? 'resolved'
        \ : s:waiting(a:thread, a:me) ? 'your turn' : 'open'
  if s:outdated(a:thread)
    let l:state .= ', outdated'
  endif
  let l:lines = [a:thread.path . (empty(l:place.range) ? '' : ':' . l:place.range)
        \ . '  ' . l:state]
  for l:c in a:thread.comments.nodes
    " Only you see a pending comment, until you submit its review
    call add(l:lines, '    ' . s:login(l:c.author) . ' (' . git_extras#age(l:c.createdAt)
          \ . (l:c.state ==# 'PENDING' ? ', pending' : '') . ')')
    call extend(l:lines, map(split(l:c.body, '\r\=\n', 1), '"      " . v:val'))
  endfor
  return l:lines
endfunction

" b:git_extras_number is :Thread's PR, 0 for :Threads, which puts each PR's
" threads under a line of its own
function! s:render() abort
  let l:number = b:git_extras_number
  let l:variables = {'owner': b:git_extras_repo[0], 'name': b:git_extras_repo[1]}
  if l:number
    let l:variables.number = l:number
  endif
  let l:data = s:graphql(b:git_extras_worktree, l:number ? s:one : s:all, l:variables)
  if l:data is v:null
    return
  endif
  let l:me = l:data.data.viewer.login
  let l:repo = l:data.data.repository
  let l:prs = l:number ? [l:repo.pullRequest] : l:repo.pullRequests.nodes
  let l:branch = FugitiveHead(0, b:git_extras_gitdir)
  let b:git_extras_threads = []
  " The thread on each line, by index into b:git_extras_threads
  let b:git_extras_line_thread = [-1]
  let l:lines = []
  let [l:open, l:waiting] = [0, 0]
  for l:pr in l:prs
    let l:all = l:pr.reviewThreads.nodes
    if !l:number
      call filter(l:all, 's:mine(v:val, l:pr, l:me)')
    endif
    for l:t in l:all
      let l:t.pr = l:pr.number
      let l:t.head = l:pr.headRefName ==# l:branch ? '' : l:pr.headRefOid
    endfor
    let l:open += len(filter(copy(l:all), '!v:val.isResolved'))
    let l:waiting += len(filter(copy(l:all), 's:waiting(v:val, l:me)'))
    let l:threads = sort(filter(copy(l:all), 'b:git_extras_resolved || !v:val.isResolved'),
          \ {a, b -> a.path ==# b.path ? s:place(a).line - s:place(b).line : a.path ># b.path ? 1 : -1})
    if !l:number
      if empty(l:threads)
        continue
      endif
      call add(l:lines, '#' . l:pr.number . '  ' . l:pr.headRefName . '  ' . l:pr.title)
      call add(b:git_extras_line_thread, -1)
    endif
    for l:t in l:threads
      let l:block = s:lines(l:t, l:me)
      if !l:number
        call map(l:block, '"  " . v:val')
      endif
      call extend(l:lines, l:block)
      call extend(b:git_extras_line_thread, repeat([len(b:git_extras_threads)], len(l:block)))
      call add(b:git_extras_threads, l:t)
    endfor
  endfor
  let l:pos = getpos('.')
  setlocal modifiable
  silent %delete _
  call setline(1, [(l:number ? '#' . l:number : 'Your threads') . ': ' . l:open . ' open, '
        \ . l:waiting . ' your turn  <CR> file  a reply  x resolve  u '
        \ . (b:git_extras_resolved ? 'hide' : 'show') . ' resolved'
        \ . '  o browser  r refresh  q close'] + l:lines)
  setlocal nomodifiable nomodified
  call git_extras#list_fit()
  call setpos('.', l:pos)
endfunction

" From :PRs, its work tree: fugitive doesn't know it in that buffer
function! git_extras#threads#open(number, ...) abort
  let l:worktree = a:0 ? a:1 : s:worktree(':Thread')
  if empty(l:worktree)
    return
  endif
  let l:number = git_extras#pr_number(l:worktree, a:number)
  if !empty(l:number)
    call s:open(l:worktree, 'thread', str2nr(l:number))
  endif
endfunction

function! git_extras#threads#all() abort
  let l:worktree = s:worktree(':Threads')
  if !empty(l:worktree)
    call s:open(l:worktree, 'threads', 0)
  endif
endfunction

function! s:worktree(command) abort
  let l:worktree = FugitiveWorkTree()
  if empty(l:worktree)
    call s:error('not in a git work tree')
    return ''
  endif
  return git_extras#require_remote(a:command) ? l:worktree : ''
endfunction

function! s:open(worktree, kind, number) abort
  let l:repo = git_extras#gh(a:worktree, 'repo view --json owner,name --jq ''.owner.login + " " + .name''')
  if l:repo is v:null
    return
  endif
  let l:gitdir = FugitiveExtractGitDir(a:worktree)
  call git_extras#list_open('git-extras://' . a:kind . '/' . fnamemodify(a:worktree, ':t'))
  let b:git_extras_worktree = a:worktree
  let b:git_extras_gitdir = l:gitdir
  let b:git_extras_number = a:number
  let b:git_extras_repo = split(trim(l:repo))
  let b:git_extras_resolved = get(b:, 'git_extras_resolved', 0)
  setlocal foldmethod=indent foldlevel=99
  nnoremap <buffer><silent> <CR> <Cmd>call <SID>goto()<CR>
  nnoremap <buffer><silent> a <Cmd>call <SID>reply()<CR>
  nnoremap <buffer><silent> x <Cmd>call <SID>toggle_resolved()<CR>
  nnoremap <buffer><silent> u <Cmd>let b:git_extras_resolved = !b:git_extras_resolved <Bar> call <SID>render()<CR>
  nnoremap <buffer><silent> o <Cmd>call <SID>browse()<CR>
  nnoremap <buffer><silent> r <Cmd>call <SID>render()<CR>
  call s:render()
  call cursor(2, 1)
endfunction

function! s:thread() abort
  let l:i = get(b:git_extras_line_thread, line('.') - 1, -1)
  return l:i < 0 ? {} : b:git_extras_threads[l:i]
endfunction

" The file at the thread's line, in the window above the list; from a commit
" when the work tree doesn't have its lines: an outdated thread's, or the head
" of a PR that isn't checked out
function! s:goto() abort
  let l:thread = s:thread()
  if empty(l:thread)
    return
  endif
  let l:place = s:place(l:thread)
  let l:worktree = b:git_extras_worktree
  if empty(l:place.commit)
    let l:file = l:worktree . '/' . l:thread.path
  else
    call system('git -C ' . shellescape(l:worktree) . ' cat-file -e '
          \ . l:place.commit . '^{commit}')
    if v:shell_error
      call s:error('commit ' . l:place.commit[:6] . ' is not here; :Git fetch first')
      return
    endif
    let l:file = FugitiveFind(l:place.commit . ':' . l:thread.path, b:git_extras_gitdir)
  endif
  if winnr('$') == 1
    aboveleft split
  else
    wincmd p
  endif
  execute 'edit' fnameescape(l:file)
  call cursor(l:place.line, 1)
  normal! zz
endfunction

" A markdown buffer above the list, as vim-review's :CommentDraft: :w posts
" the reply (writing again edits it), :q! before writing drops it
function! s:reply() abort
  let l:thread = s:thread()
  if empty(l:thread)
    return
  endif
  let l:list = bufnr('')
  let l:place = s:place(l:thread)
  execute 'aboveleft' get(g:, 'review_comment_height', 10) . 'new'
  setlocal buftype=acwrite bufhidden=wipe noswapfile filetype=markdown
  execute 'file' fnameescape('git-extras://reply/' . l:thread.pr
        \ . '/' . l:thread.path . (empty(l:place.range) ? '' : ':' . l:place.range))
  let b:git_extras_reply = {'list': l:list, 'worktree': getbufvar(l:list, 'git_extras_worktree'),
        \ 'thread': l:thread.id, 'comment': ''}
  augroup git_extras_reply
    autocmd! * <buffer>
    autocmd BufWriteCmd <buffer> call s:post()
  augroup END
  startinsert
endfunction

function! s:post() abort
  let l:r = b:git_extras_reply
  let l:body = trim(join(getline(1, '$'), "\n"))
  if empty(l:body)
    call s:error('empty reply, not posted')
    return
  endif
  if empty(l:r.comment)
    let l:data = s:graphql(l:r.worktree, s:reply, {'thread': l:r.thread, 'body': l:body})
    if l:data is v:null
      return
    endif
    let l:comment = l:data.data.addPullRequestReviewThreadReply.comment
    let l:r.comment = l:comment.id
    let l:state = l:comment.state
  else
    let l:data = s:graphql(l:r.worktree, s:edit, {'comment': l:r.comment, 'body': l:body})
    if l:data is v:null
      return
    endif
    let l:state = l:data.data.updatePullRequestReviewComment.pullRequestReviewComment.state
  endif
  setlocal nomodified
  if bufwinid(l:r.list) > 0
    call win_execute(bufwinid(l:r.list), 'call s:render()')
  endif
  " With a review of yours pending on the PR, GitHub adds the reply to it
  echo l:state ==# 'PENDING'
        \ ? 'Reply added to your pending review; submit it on GitHub to post it'
        \ : 'Reply posted; :q to close, or edit and :w again to change it'
endfunction

function! s:toggle_resolved() abort
  let l:thread = s:thread()
  if empty(l:thread)
    return
  endif
  let l:mutation = l:thread.isResolved ? 'unresolveReviewThread' : 'resolveReviewThread'
  if s:graphql(b:git_extras_worktree, printf(s:resolve, l:mutation),
        \ {'thread': l:thread.id}) isnot v:null
    call s:render()
  endif
endfunction

" The thread's PR, or on one of :Threads' PR lines, that PR
function! s:browse() abort
  let l:thread = s:thread()
  let l:number = !empty(l:thread) ? l:thread.pr
        \ : b:git_extras_number ? b:git_extras_number
        \ : str2nr(matchstr(getline('.'), '^#\zs\d\+'))
  if l:number
    call git_extras#gh(b:git_extras_worktree, 'pr view --web ' . l:number)
  endif
endfunction
