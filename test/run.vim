" Headless tests, from the repository's root:
"   vim -Nu NONE -i NONE -Es -S test/run.vim
" Prints one line per test and exits non-zero when one fails; TEST=<pattern>
" in the environment runs the tests whose names match. gh is test/bin/gh, with
" canned answers. The plugins it needs are vim-plug's copies, unless $FUGITIVE
" or $VIM_LISTS name others.
set nocompatible hidden
let s:root = expand('<sfile>:p:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let $PATH = s:root . '/test/bin:' . $PATH
" Only these plugins: Vim's own ones aren't all quiet in silent Ex mode
for [s:var, s:name, s:file] in [['FUGITIVE', 'vim-fugitive', 'fugitive.vim'],
      \ ['VIM_LISTS', 'vim-lists', 'roumail_lists.vim']]
  let s:dir = fnamemodify(empty(eval('$' . s:var)) ? expand('~/.vim/plugged/' . s:name)
        \ : eval('$' . s:var), ':p:s?/$??')
  execute 'set runtimepath^=' . fnameescape(s:dir)
  execute 'source' fnameescape(s:dir . '/plugin/' . s:file)
endfor
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
  call assert_equal('T1', roumail_lists#item().id)
  normal =
  call assert_equal(3, line('$'))
  " u shows the resolved thread, in file order
  normal u
  call assert_equal('a.py:1  resolved  (1)  sam: done', getline(2))
  call assert_equal('T1', roumail_lists#item().id, 'still on its thread')
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
  call assert_equal({}, roumail_lists#item())
  call assert_equal(7, roumail_lists#row().pr)
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
