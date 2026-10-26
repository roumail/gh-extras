" :Threads: a PR's review threads with their conversations, in a window at
" the bottom, to read the replies to your comments, answer them and resolve
" them without the GitHub UI. Replies post at once, as GitHub's Reply does.

let s:query = 'query($owner: String!, $name: String!, $number: Int!) {'
      \ . ' viewer { login }'
      \ . ' repository(owner: $owner, name: $name) { pullRequest(number: $number) {'
      \ . ' reviewThreads(first: 100) { nodes {'
      \ . ' id isResolved isOutdated path line startLine originalLine originalStartLine'
      \ . ' comments(first: 100) { nodes {'
      \ . ' author { login } body createdAt state originalCommit { oid } } } } } } } }'

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

" Where the thread is: on the PR's head, or, once its lines have changed
" (outdated), on the commit it was made on. line is null for a comment on the
" whole file.
function! s:place(thread) abort
  let l:outdated = a:thread.isOutdated || a:thread.line is v:null
  let l:line = l:outdated ? a:thread.originalLine : a:thread.line
  let l:start = l:outdated ? a:thread.originalStartLine : a:thread.startLine
  return {
        \ 'commit': l:outdated ? a:thread.comments.nodes[0].originalCommit.oid : '',
        \ 'line': l:line is v:null ? 1 : l:line,
        \ 'range': l:line is v:null ? '' : (l:start is v:null ? '' : l:start . '-') . l:line,
        \ }
endfunction

" Open, and the last word isn't yours
function! s:waiting(thread, me) abort
  return !a:thread.isResolved
        \ && s:login(a:thread.comments.nodes[-1].author) !=? a:me
endfunction

function! s:lines(thread, me) abort
  let l:place = s:place(a:thread)
  let l:state = a:thread.isResolved ? 'resolved'
        \ : s:waiting(a:thread, a:me) ? 'your turn' : 'open'
  if !empty(l:place.commit)
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

function! s:render() abort
  let l:data = s:graphql(b:git_extras_worktree, s:query, {'number': b:git_extras_number,
        \ 'owner': b:git_extras_repo[0], 'name': b:git_extras_repo[1]})
  if l:data is v:null
    return
  endif
  let l:me = l:data.data.viewer.login
  let l:pr = l:data.data.repository.pullRequest
  let l:all = l:pr.reviewThreads.nodes
  let l:threads = sort(filter(copy(l:all), 'b:git_extras_resolved || !v:val.isResolved'),
        \ {a, b -> a.path ==# b.path ? s:place(a).line - s:place(b).line : a.path ># b.path ? 1 : -1})
  let b:git_extras_threads = l:threads
  " The thread on each line, by index into b:git_extras_threads
  let b:git_extras_line_thread = [-1]
  let l:lines = []
  for l:i in range(len(l:threads))
    let l:block = s:lines(l:threads[l:i], l:me)
    call extend(l:lines, l:block)
    call extend(b:git_extras_line_thread, repeat([l:i], len(l:block)))
  endfor
  let l:open = len(filter(copy(l:all), '!v:val.isResolved'))
  let l:waiting = len(filter(copy(l:all), 's:waiting(v:val, l:me)'))
  let l:pos = getpos('.')
  setlocal modifiable
  silent %delete _
  call setline(1, ['#' . b:git_extras_number . ': ' . l:open . ' open, ' . l:waiting
        \ . ' your turn  <CR> file  a reply  x resolve  u '
        \ . (b:git_extras_resolved ? 'hide' : 'show') . ' resolved'
        \ . '  o browser  r refresh  q close'] + l:lines)
  setlocal nomodifiable nomodified
  call git_extras#list_fit()
  call setpos('.', l:pos)
endfunction

function! git_extras#threads#open(number) abort
  let l:worktree = FugitiveWorkTree()
  if empty(l:worktree)
    call s:error('not in a git work tree')
    return
  endif
  if !git_extras#require_remote(':Threads')
    return
  endif
  let l:number = git_extras#pr_number(l:worktree, a:number)
  if empty(l:number)
    return
  endif
  let l:repo = git_extras#gh(l:worktree, 'repo view --json owner,name --jq ''.owner.login + " " + .name''')
  if l:repo is v:null
    return
  endif
  call git_extras#list_open('git-extras://threads/' . fnamemodify(l:worktree, ':t'))
  let b:git_extras_worktree = l:worktree
  let b:git_extras_gitdir = FugitiveGitDir()
  let b:git_extras_number = str2nr(l:number)
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

" The file at the thread's line, in the window above the list; an outdated
" thread's from the commit it was made on, since the lines are no longer in
" the work tree
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
  execute 'file' fnameescape('git-extras://reply/' . getbufvar(l:list, 'git_extras_number')
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

function! s:browse() abort
  call git_extras#gh(b:git_extras_worktree, 'pr view --web ' . b:git_extras_number)
endfunction
