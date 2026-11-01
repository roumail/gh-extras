if exists('g:loaded_git_extras')
  finish
endif
let g:loaded_git_extras = 1

" roumail/vim-requires is optional
try
  call roumail_requires#check('git-extras', {
        \ 'tpope/vim-fugitive': 'g:loaded_fugitive',
        \ 'roumail/vim-draft': 'g:loaded_roumail_draft',
        \ })
catch /^Vim\%((\a\+)\)\=:E117:/
endtry

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
