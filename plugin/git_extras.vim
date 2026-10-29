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

" Warns at startup when a required plugin isn't loaded (roumail/vim-requires)
try
  call roumail_requires#check('git-extras', {
        \ 'tpope/vim-fugitive': 'g:loaded_fugitive',
        \ })
catch /^Vim\%((\a\+)\)\=:E117:/
endtry

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
" Close the :BranchDiff comparison (name, else this tab's), which stays in
" :Compares; outside one, the fugitive side of the diff in this tab
command! -nargs=? -complete=customlist,git_extras#compares#complete
      \ DiffClose call git_extras#diff_close(<q-args>)
" The :BranchDiff comparisons of this session; <CR> reopens one, d removes
command! Compares call git_extras#compares#show()

if executable('gh')
  " Open PRs (default 20), latest first; <CR> checks one out
  command! -nargs=? PRs call git_extras#prs#open(<q-args>)
  " Review threads on the branch's PR (or number), to reply and resolve
  command! -nargs=? Thread call git_extras#threads#open(<q-args>)
  " The review threads you're in, across the open PRs
  command! Threads call git_extras#threads#all()
  " Post vim-review's comments as a pending review on the branch's PR (or
  " number)
  command! -nargs=? CommentsSubmit call git_extras#comments#submit(<q-args>)
endif

nnoremap <Plug>(git-extras-diff-this) <Cmd>DiffThis<CR>
nnoremap <Plug>(git-extras-diff-main) <Cmd>DiffThis!<CR>
nnoremap <Plug>(git-extras-branch-diff) <Cmd>BranchDiff<CR>
nnoremap <Plug>(git-extras-branch-commits) <Cmd>BranchCommits<CR>
nnoremap <Plug>(git-extras-diff-close) <Cmd>DiffClose<CR>
nnoremap <Plug>(git-extras-compares) <Cmd>Compares<CR>

" vim-review's review comments: on the branch side of a diff, saved per
" branch. Set up once every plugin has loaded, when the guards tell whether
" vim-review and fugitive are installed.
function! s:review() abort
  if exists('g:loaded_review') && exists('g:loaded_fugitive')
    call git_extras#comments#init()
  endif
endfunction

augroup git_extras
  autocmd!
  " Warn after a :Git checkout that left unsaved comments from another branch
  autocmd User FugitiveChanged call git_extras#comments#check()
  autocmd VimEnter * ++once call s:review()
augroup END
if v:vim_did_enter
  call s:review()
endif
