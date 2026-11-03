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
      \ . ' comment { state } } }'

let s:resolve = 'mutation($thread: ID!) {'
      \ . ' %s(input: {threadId: $thread}) { thread { isResolved } } }'

function! s:graphql(worktree, query, variables) abort
  let l:out = gh_extras#gh(a:worktree, 'api graphql --input -',
        \ json_encode({'query': a:query, 'variables': a:variables}))
  return l:out is v:null ? v:null : json_decode(l:out)
endfunction

function! s:login(author) abort
  return type(a:author) == v:t_dict ? a:author.login : 'ghost'
endfunction

function! s:outdated(thread) abort
  return a:thread.isOutdated || a:thread.line is v:null
endfunction

function! s:place(thread) abort
  let l:outdated = s:outdated(a:thread)
  let l:line = l:outdated ? a:thread.originalLine : a:thread.line
  let l:start = l:outdated ? a:thread.originalStartLine : a:thread.startLine
  " line is null for a comment on the whole file
  return {
        \ 'commit': l:outdated ? a:thread.comments.nodes[0].originalCommit.oid : a:thread.head,
        \ 'line': l:line is v:null ? 1 : l:line,
        \ 'range': l:line is v:null ? '' : (l:start is v:null ? '' : l:start . '-') . l:line,
        \ }
endfunction

function! s:waiting(thread, me) abort
  return !a:thread.isResolved
        \ && s:login(a:thread.comments.nodes[-1].author) !=? a:me
endfunction

function! s:render() abort
  let l:number = b:gh_extras_number
  let l:variables = {'owner': b:gh_extras_repo[0], 'name': b:gh_extras_repo[1]}
  if l:number
    let l:variables.number = l:number
  endif
  let l:data = s:graphql(b:gh_extras_worktree, l:number ? s:one : s:all, l:variables)
  if l:data is v:null
    return
  endif
  let l:me = l:data.data.viewer.login
  let l:repo = l:data.data.repository
  let l:prs = l:number ? [l:repo.pullRequest] : l:repo.pullRequests.nodes
  let l:branch = FugitiveHead(0, b:gh_extras_gitdir)
  for l:pr in l:prs
    if !l:number
      call filter(l:pr.reviewThreads.nodes, {_, t -> s:login(l:pr.author) ==? l:me
            \ || !empty(filter(copy(t.comments.nodes), 's:login(v:val.author) ==? l:me'))})
    endif
    for l:t in l:pr.reviewThreads.nodes
      let l:t.pr = l:pr.number
      let l:t.head = l:pr.headRefName ==# l:branch ? '' : l:pr.headRefOid
    endfor
  endfor
  let b:gh_extras_fetched = {'me': l:me, 'prs': l:prs}
  call s:draw()
endfunction

function! s:draw() abort
  let l:number = b:gh_extras_number
  let l:me = b:gh_extras_fetched.me
  let b:gh_extras_threads = []
  let b:gh_extras_line_thread = [-1]
  let l:lines = []
  let [l:open, l:waiting] = [0, 0]
  for l:pr in b:gh_extras_fetched.prs
    let l:all = l:pr.reviewThreads.nodes
    let l:open += len(filter(copy(l:all), '!v:val.isResolved'))
    let l:waiting += len(filter(copy(l:all), 's:waiting(v:val, l:me)'))
    let l:threads = sort(filter(copy(l:all), 'b:gh_extras_resolved || !v:val.isResolved'),
          \ {a, b -> a.path ==# b.path ? s:place(a).line - s:place(b).line : a.path ># b.path ? 1 : -1})
    if !l:number
      if empty(l:threads)
        continue
      endif
      call add(l:lines, '#' . l:pr.number . '  ' . l:pr.headRefName . '  ' . l:pr.title)
      call add(b:gh_extras_line_thread, -1)
    endif
    for l:t in l:threads
      " A thread is one line; = opens it to the conversation, as fugitive's =
      " does a file's diff
      let l:place = s:place(l:t)
      let l:head = l:t.path . (empty(l:place.range) ? '' : ':' . l:place.range) . '  '
            \ . (l:t.isResolved ? 'resolved' : s:waiting(l:t, l:me) ? 'your turn' : 'open')
            \ . (s:outdated(l:t) ? ', outdated' : '')
      if has_key(b:gh_extras_open, l:t.id)
        let l:block = [l:head]
        for l:c in l:t.comments.nodes
          " Only you see a pending comment, until you submit its review
          call add(l:block, '    ' . s:login(l:c.author) . ' (' . gh_extras#age(l:c.createdAt)
                \ . (l:c.state ==# 'PENDING' ? ', pending' : '') . ')')
          call extend(l:block, map(split(l:c.body, '\r\=\n', 1), '"      " . v:val'))
        endfor
      else
        let l:last = l:t.comments.nodes[-1]
        let l:block = [l:head . '  (' . len(l:t.comments.nodes) . ')  ' . s:login(l:last.author)
              \ . ': ' . get(split(l:last.body, '\r\=\n'), 0, '')]
      endif
      if !l:number
        call map(l:block, '"  " . v:val')
      endif
      call extend(l:lines, l:block)
      call extend(b:gh_extras_line_thread, repeat([len(b:gh_extras_threads)], len(l:block)))
      call add(b:gh_extras_threads, l:t)
    endfor
  endfor
  let l:pos = getpos('.')
  setlocal modifiable
  silent %delete _
  call setline(1, [(l:number ? '#' . l:number : 'Your threads') . ': ' . l:open . ' open, '
        \ . l:waiting . ' your turn  = open/close  <CR> file  :Reply  x resolve  u '
        \ . (b:gh_extras_resolved ? 'hide' : 'show') . ' resolved'
        \ . '  o browser  r refresh  q close'] + l:lines)
  setlocal nomodifiable nomodified
  call gh_extras#list_fit()
  call setpos('.', l:pos)
endfunction

" From :PRs, its work tree: fugitive doesn't know it in that buffer
function! gh_extras#threads#open(number, ...) abort
  let l:worktree = a:0 ? a:1 : gh_extras#github_worktree(':Thread')
  if empty(l:worktree)
    return
  endif
  let l:number = gh_extras#pr_number(l:worktree, a:number)
  if !empty(l:number)
    call s:open(l:worktree, 'thread', str2nr(l:number))
  endif
endfunction

function! gh_extras#threads#all() abort
  let l:worktree = gh_extras#github_worktree(':Threads')
  if !empty(l:worktree)
    call s:open(l:worktree, 'threads', 0)
  endif
endfunction

function! s:open(worktree, kind, number) abort
  let l:repo = gh_extras#gh(a:worktree, 'repo view --json owner,name --jq ''.owner.login + " " + .name''')
  if l:repo is v:null
    return
  endif
  call gh_extras#list_open('gh-extras://' . a:kind . '/' . fnamemodify(a:worktree, ':t'))
  let b:gh_extras_worktree = a:worktree
  let b:gh_extras_gitdir = FugitiveExtractGitDir(a:worktree)
  let b:gh_extras_number = a:number
  let b:gh_extras_repo = split(trim(l:repo))
  let b:gh_extras_resolved = get(b:, 'gh_extras_resolved', 0)
  let b:gh_extras_open = get(b:, 'gh_extras_open', {})
  nnoremap <buffer><silent> <CR> <Cmd>call <SID>goto()<CR>
  nnoremap <buffer><silent> = <Cmd>call <SID>toggle_open()<CR>
  command! -buffer -nargs=* Reply call gh_extras#threads#reply(<q-args>)
  command! -buffer -nargs=* ReplyDraft call gh_extras#threads#reply_draft(<q-args>)
  nnoremap <buffer><silent> x <Cmd>call <SID>toggle_resolved()<CR>
  nnoremap <buffer><silent> u <Cmd>let b:gh_extras_resolved = !b:gh_extras_resolved <Bar> call <SID>draw()<CR>
  nnoremap <buffer><silent> o <Cmd>call <SID>browse()<CR>
  nnoremap <buffer><silent> r <Cmd>call <SID>render()<CR>
  call s:render()
  call cursor(2, 1)
endfunction

function! s:thread() abort
  let l:i = get(b:gh_extras_line_thread, line('.') - 1, -1)
  return l:i < 0 ? {} : b:gh_extras_threads[l:i]
endfunction

function! s:toggle_open() abort
  let l:thread = s:thread()
  if empty(l:thread)
    return
  endif
  if has_key(b:gh_extras_open, l:thread.id)
    call remove(b:gh_extras_open, l:thread.id)
  else
    let b:gh_extras_open[l:thread.id] = 1
  endif
  let l:i = index(b:gh_extras_threads, l:thread)
  call s:draw()
  call cursor(index(b:gh_extras_line_thread, l:i) + 1, 1)
endfunction

function! s:goto() abort
  let l:thread = s:thread()
  if empty(l:thread)
    return
  endif
  let l:place = s:place(l:thread)
  let l:worktree = b:gh_extras_worktree
  if empty(l:place.commit)
    let l:file = l:worktree . '/' . l:thread.path
  else
    call system('git -C ' . shellescape(l:worktree) . ' cat-file -e '
          \ . l:place.commit . '^{commit}')
    if v:shell_error
      call gh_extras#error('commit ' . l:place.commit[:6] . ' is not here; :Git fetch first')
      return
    endif
    let l:file = FugitiveFind(l:place.commit . ':' . l:thread.path, b:gh_extras_gitdir)
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

" Text typed at the :Reply prompt and left with <Esc>, by thread id, to start
" from when replying to that thread again
let s:unsent = {}

" The thread under the cursor and its label, path:range; {} when not on one
function! s:target() abort
  if !exists('b:gh_extras_threads')
    call gh_extras#error('not in a :Thread or :Threads list')
    return {}
  endif
  let l:thread = s:thread()
  if empty(l:thread)
    call gh_extras#error('not on a thread')
    return {}
  endif
  let l:range = s:place(l:thread).range
  return {'thread': l:thread,
        \ 'label': l:thread.path . (empty(l:range) ? '' : ':' . l:range)}
endfunction

" :Reply: posts text, or what is typed at the prompt, to the thread under the
" cursor. What was typed and left with <Esc> is kept for the next :Reply or
" :ReplyDraft on that thread, so you can look something up and go on.
function! gh_extras#threads#reply(text) abort
  let l:target = s:target()
  if empty(l:target)
    return
  endif
  let l:id = l:target.thread.id
  let l:text = a:text
  if empty(l:text)
    let s:typed = get(s:unsent, l:id, '')
    " CmdlineLeave is too late: <Esc> has emptied the line by then
    augroup gh_extras_reply
      autocmd!
      autocmd CmdlineChanged @ let s:typed = getcmdline()
    augroup END
    try
      let l:text = input('Reply ' . l:target.label . ': ', s:typed)
    finally
      autocmd! gh_extras_reply
    endtry
    if empty(l:text) && !empty(s:typed)
      let s:unsent[l:id] = s:typed
      redraw
      echo 'Reply kept: :Reply or :ReplyDraft on ' . l:target.label . ' goes on from it'
      return
    endif
  endif
  silent! call remove(s:unsent, l:id)
  if empty(trim(l:text))
    return
  endif
  redraw
  call s:post(bufnr(''), b:gh_extras_worktree, l:id, trim(l:text))
endfunction

" :ReplyDraft (a): the reply in a vim-draft draft above the list, starting
" with text, else with what was left at the :Reply prompt on that thread
function! gh_extras#threads#reply_draft(text) abort
  let l:target = s:target()
  if empty(l:target)
    return
  endif
  let l:id = l:target.thread.id
  let l:text = empty(a:text) ? get(s:unsent, l:id, '') : a:text
  silent! call remove(s:unsent, l:id)
  call roumail_draft#open('gh-extras://reply/' . l:target.thread.pr . '/' . l:target.label,
        \ empty(l:text) ? [] : [l:text],
        \ function('s:post', [bufnr(''), b:gh_extras_worktree, l:id]),
        \ {'split': 'aboveleft '
        \     . get(g:, 'gh_extras_reply_height', get(g:, 'review_comment_height', 10)) . 'new',
        \  'saved': 'Reply saved: closing posts it',
        \  'empty': 'Reply empty: closing posts nothing'})
  setlocal filetype=markdown
endfunction

function! s:post(list, worktree, thread, text) abort
  let l:data = s:graphql(a:worktree, s:reply, {'thread': a:thread, 'body': a:text})
  if l:data is v:null
    " The draft is gone by now
    call setreg('"', a:text)
    call gh_extras#error('reply not posted; its text is in the unnamed register')
    return
  endif
  if bufwinid(a:list) > 0
    call win_execute(bufwinid(a:list), 'call s:render()')
  endif
  " With a review of yours pending on the PR, GitHub adds the reply to it
  echo l:data.data.addPullRequestReviewThreadReply.comment.state ==# 'PENDING'
        \ ? 'Reply added to your pending review; submit it on GitHub to post it'
        \ : 'Reply posted'
endfunction

function! s:toggle_resolved() abort
  let l:thread = s:thread()
  if empty(l:thread)
    return
  endif
  if s:graphql(b:gh_extras_worktree,
        \ printf(s:resolve, l:thread.isResolved ? 'unresolveReviewThread' : 'resolveReviewThread'),
        \ {'thread': l:thread.id}) isnot v:null
    call s:render()
  endif
endfunction

function! s:browse() abort
  let l:thread = s:thread()
  let l:number = !empty(l:thread) ? l:thread.pr
        \ : b:gh_extras_number ? b:gh_extras_number
        \ : str2nr(matchstr(getline('.'), '^#\zs\d\+'))
  if l:number
    call gh_extras#gh(b:gh_extras_worktree, 'pr view --web ' . l:number)
  endif
endfunction
