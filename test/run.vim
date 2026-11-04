" Headless tests, from the repository's root:
"   vim -Nu NONE -i NONE -Es -S test/run.vim
" Prints one line per test and exits non-zero when one fails; TEST=<pattern>
" in the environment runs the tests whose names match. gh is test/bin/gh, with
" canned answers; fugitive is vim-plug's copy, unless $FUGITIVE names another.
set nocompatible hidden
let s:root = expand('<sfile>:p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let $PATH = s:root . '/test/bin:' . $PATH
let s:fugitive = fnamemodify(empty($FUGITIVE) ? expand('~/.vim/plugged/vim-fugitive')
      \ : $FUGITIVE, ':p:s?/$??')
execute 'set runtimepath^=' . fnameescape(s:fugitive)
" Only these plugins: Vim's own ones aren't all quiet in silent Ex mode
execute 'source' fnameescape(s:fugitive . '/plugin/fugitive.vim')
execute 'source' fnameescape(s:root . '/plugin/gh_extras.vim')

let s:tmp = resolve(tempname())
let s:repo = s:tmp . '/repo'
let s:out = []

function! s:reset() abort
  silent! %bwipeout!
  call delete(s:tmp, 'rf')
  call mkdir(s:repo, 'p')
  call system('git -C ' . shellescape(s:repo) . ' init -q -b main && git -C '
        \ . shellescape(s:repo) . ' remote add origin https://github.com/o/r')
  execute 'cd' fnameescape(s:repo)
  execute 'edit' fnameescape(s:repo . '/x.txt')
endfunction

function! s:lines() abort
  return getline(1, '$')
endfunction

" The list module alone, with a list of words
function! s:test_list_module() abort
  let g:words = ['apple', 'banana', 'cherry']
  call gh_extras#list#open('test://words', {
        \ 'fetch': {-> copy(g:words)},
        \ 'heading': {items -> ['Words (' . len(items) . ')']},
        \ 'rows': {items -> map(copy(items), {_, w -> {'lines': [w], 'item': {'w': w}}})},
        \ 'id': {item -> item.w}, 'match': {item -> item.w},
        \ 'keys': [{'key': 'x', 'hint': 'pick', 'call': {-> execute('let g:picked = gh_extras#list#item().w')}},
        \          {'key': ':Cmd'}]}, {'mine': 1})
  call assert_equal(1, b:mine)
  call assert_equal(['Words (3)  x pick  :Cmd  / filter  r refresh  q close',
        \ 'apple', 'banana', 'cherry'], s:lines())
  call assert_equal(2, line('.'), 'on the first item')
  call cursor(1, 1)
  call assert_equal({}, gh_extras#list#item(), 'the heading has no item')
  call cursor(3, 1)
  normal x
  call assert_equal('banana', g:picked)
  " Refreshing keeps the cursor on its item, wherever it moves to
  let g:words = ['zebra', 'apple', 'banana']
  normal r
  call assert_equal('banana', getline('.'))
  " The filter: typed after /, kept with <CR>, in the heading
  call feedkeys("/an\<CR>", 'x')
  call assert_equal(['Words (3), 1 matching ''an''  x pick  :Cmd  / filter  r refresh  q close',
        \ 'banana'], s:lines())
  call feedkeys("/\<C-u>\<CR>", 'x')
  call assert_equal(4, line('$'))
  " <Esc> goes back to the filter it had
  call feedkeys("/zz\<Esc>", 'x')
  call assert_equal(4, line('$'))
  " A fetch failing leaves the list as it was
  let g:words = v:null
  normal r
  call assert_equal(4, line('$'))
  normal q
  call assert_false(bufexists('test://words'))
endfunction

function! s:test_prs() abort
  PRs
  call assert_equal('gh-extras://prs/repo', bufname())
  call assert_match('^Open PRs (2)  <CR> checkout  t threads  o browser  / filter  r refresh  q close$',
        \ getline(1))
  call assert_match('^#\s\+who\s\+title', getline(2))
  call assert_match('^#7 \+mira \+Fix login \+fix-login \+approved ', getline(3))
  call assert_match('^#8 \+sam \+Add search \+search \+draft ', getline(4))
  call assert_equal(3, line('.'))
  call feedkeys("/search\<CR>", 'x')
  call assert_match('^Open PRs (2), 1 matching ''search''', getline(1))
  call assert_equal(3, line('$'))
  call assert_match('^#8 ', getline('.'))
endfunction

function! s:test_thread() abort
  Thread 7
  call assert_equal('gh-extras://thread/repo', bufname())
  call assert_equal(['#7: 2 open, 1 your turn  = open/close  <CR> file  :Reply  x resolve'
        \ . '  u resolved  o browser  / filter  r refresh  q close',
        \ 'a.py:9  open  (1)  me: nit',
        \ 'b.py:3  your turn  (2)  mira: because'], s:lines())
  call assert_equal(2, line('.'))
  " = opens the thread under the cursor, which stays on it
  call cursor(3, 1)
  normal =
  call assert_equal(['b.py:3  your turn', '    me (', '      why?'],
        \ [getline(3), getline(4)[:7], getline(5)])
  call assert_equal(3, line('.'))
  call assert_equal('T1', gh_extras#list#item().id)
  normal =
  call assert_equal(3, line('$'))
  " u shows the resolved thread, in file order
  normal u
  call assert_equal('a.py:1  resolved  (1)  sam: done', getline(2))
  call assert_equal('T1', gh_extras#list#item().id, 'still on its thread')
  " Opening it again, from the file, keeps u
  wincmd p
  Thread 7
  call assert_equal('gh-extras://thread/repo', bufname())
  call assert_equal(4, line('$'))
  call feedkeys("/sam\<CR>", 'x')
  call assert_equal(['a.py:1  resolved  (1)  sam: done'], getline(2, '$'))
endfunction

function! s:test_threads() abort
  Threads
  call assert_equal('gh-extras://threads/repo', bufname())
  call assert_match('^Your threads: 2 open, 1 your turn  = open/close', getline(1))
  call assert_equal(['#7  fix-login  Fix login', '  a.py:9  open  (1)  me: nit',
        \ '  b.py:3  your turn  (2)  mira: because'], getline(2, '$'))
  call assert_equal(3, line('.'), 'on the first thread, not its PR')
  call cursor(2, 1)
  call assert_equal({}, gh_extras#list#item())
  call assert_equal(7, gh_extras#list#row().pr)
  " :Reply needs a thread under the cursor
  call assert_true(exists(':Reply') == 2)
endfunction

let s:prefix = expand('<SID>') . 'test_'
let s:failed = 0
let s:names = []
for s:line in split(execute('function'), "\n")
  if stridx(s:line, 'function ' . s:prefix) == 0
    call add(s:names, matchstr(s:line, '^function \zs[^(]\+'))
  endif
endfor
for s:name in s:names
  let s:label = matchstr(s:name, 'test_\zs\w\+')
  if !empty($TEST) && s:label !~# $TEST
    continue
  endif
  call s:reset()
  let v:errors = []
  try
    call call(s:name, [])
  catch
    call add(v:errors, v:exception . ' @ ' . v:throwpoint)
  endtry
  if empty(v:errors)
    call add(s:out, 'ok   ' . s:label)
  else
    let s:failed += 1
    call add(s:out, 'FAIL ' . s:label)
    call extend(s:out, map(copy(v:errors), '"     " . v:val'))
  endif
endfor
call add(s:out, s:failed ? s:failed . ' failed' : 'all passed')
call writefile(s:out, '/dev/stdout')
cd /
call delete(s:tmp, 'rf')
execute 'cquit' (s:failed ? 1 : 0)
