" git-extras: additions to vim-fugitive. Review a branch against the repo's
" default branch (main/master), keeping each review as a comparison, stage
" hunks in a vertical diff, list open PRs and answer their review threads.
" With roumail/vim-review, its review comments go on fugitive diffs, are saved
" per branch and post to the PR. Commands and <Plug> mappings only; no keys
" are bound here. Requires tpope/vim-fugitive; the GitHub commands need gh.
if exists('g:loaded_git_extras')
  finish
endif
let g:loaded_git_extras = 1

" Required plugins are checked once every plugin has loaded (VimEnter, or now
" when loaded later): their g:loaded_* guards tell whether they are installed.
" Without them nothing below is defined.
function! s:init() abort
  let l:missing = filter({
        \ 'tpope/vim-fugitive': 'g:loaded_fugitive',
        \ }, '!exists(v:val)')
  if !empty(l:missing)
    echohl WarningMsg
    echomsg 'git-extras: not loaded, requires ' . join(sort(keys(l:missing)), ', ')
    echohl None
    return
  endif

  " Index | working tree: dp/do move hunks, :w in the index buffer stages.
  " With !, the file at the merge-base with main | working tree (what the PR
  " changes).
  command! -bang DiffThis call git_extras#diff_this(<bang>0)
  " The commands below take an optional branch (default HEAD), e.g.
  " origin/feature, to review it without checking it out.
  " One tab per changed file, each a diff against the merge-base with main
  command! -nargs=? -complete=customlist,git_extras#complete_branch
        \ BranchDiff call git_extras#branch_diff(<q-args>)
  " Commits on the branch that main doesn't have; further args go to git log
  command! -nargs=* -complete=customlist,git_extras#complete_commits
        \ BranchCommits call git_extras#branch_commits(<q-args>)
  " Close the fugitive side of the diff in this tab and turn diff mode off
  command! DiffClose call git_extras#diff_close()
  " Close the tabs of a :BranchDiff comparison; it stays in :Compares
  command! -nargs=1 -complete=customlist,git_extras#compares#complete
        \ CompareClose call git_extras#compares#close(<q-args>)
  " The :BranchDiff comparisons of this session; <CR> reopens one, d removes
  command! Compares call git_extras#compares#show()

  if executable('gh')
    " Open PRs (default 20), latest first; <CR> checks one out
    command! -nargs=? PRs call git_extras#prs#open(<q-args>)
    " Review threads on the branch's PR (or number), to reply and resolve
    command! -nargs=? Threads call git_extras#threads#open(<q-args>)
  endif

  nnoremap <Plug>(git-extras-diff-this) <Cmd>DiffThis<CR>
  nnoremap <Plug>(git-extras-diff-main) <Cmd>DiffThis!<CR>
  nnoremap <Plug>(git-extras-branch-diff) <Cmd>BranchDiff<CR>
  nnoremap <Plug>(git-extras-branch-commits) <Cmd>BranchCommits<CR>
  nnoremap <Plug>(git-extras-diff-close) <Cmd>DiffClose<CR>
  nnoremap <Plug>(git-extras-compares) <Cmd>Compares<CR>

  " vim-review's review comments: on the branch side of a diff, saved per
  " branch, and posted to the PR
  if exists('g:loaded_review')
    call git_extras#comments#init()
    if executable('gh')
      " Post the comments as a pending review on the branch's PR (or number)
      command! -nargs=? CommentsSubmit call git_extras#comments#submit(<q-args>)
    endif
    " Warn after a :Git checkout that left unsaved comments from another branch
    augroup git_extras
      autocmd!
      autocmd User FugitiveChanged call git_extras#comments#check()
    augroup END
  endif
endfunction

if v:vim_did_enter
  call s:init()
else
  augroup git_extras_init
    autocmd!
    autocmd VimEnter * ++once call s:init()
  augroup END
endif
