if exists('g:loaded_gh_extras')
  finish
endif
let g:loaded_gh_extras = 1

" roumail/vim-requires is optional
try
  call roumail_requires#check('gh-extras', {
        \ 'tpope/vim-fugitive': 'g:loaded_fugitive',
        \ 'roumail/vim-draft': 'g:loaded_roumail_draft',
        \ })
catch /^Vim\%((\a\+)\)\=:E117:/
endtry

if executable('gh')
  " Open PRs (default 20), latest first; <CR> checks one out
  command! -nargs=? PRs call gh_extras#prs#open(<q-args>, 0)
  " Merged PRs (default 50), latest merged first; <CR> shows the merge commit
  command! -nargs=? MergedPRs call gh_extras#prs#open(<q-args>, 1)
  " Review threads on the branch's PR (or number), to reply and resolve
  command! -nargs=? Thread call gh_extras#threads#open(<q-args>)
  " The review threads you're in, across the open PRs
  command! Threads call gh_extras#threads#all()
  " Post vim-review's comments as a pending review on the branch's PR (or
  " number)
  command! -nargs=? CommentsSubmit call gh_extras#comments#submit(<q-args>)
endif
