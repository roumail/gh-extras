# gh-extras

GitHub pull requests from Vim, through [gh](https://cli.github.com): list the
open ones and check one out, look back through the merged ones, read and answer their review threads, and post
[vim-review](https://github.com/roumail/vim-review)'s comments as a pending
review. Built on [vim-fugitive](https://github.com/tpope/vim-fugitive); to
review a branch's diffs, see
[fugitive-extras](https://github.com/roumail/fugitive-extras).

## Open and merged pull requests

`:PRs [count]` lists the repo's open pull requests, most recently updated first
(default 20, at most 100), in a window at the bottom, under a line of column headings:
number, who opened it, title, branch, review state (`draft`, `approved`,
`changes`, `review`, or `-`) and age.

Who opened it is their login, or a readable name for it from a file of
`name:login` lines (`Mira:mira-dev`, logins in any case), read on each refresh.

```vim
let g:gh_extras_pr_authors = '~/.config/gh-pr-authors.txt'  " the default
```

| Key | What it does |
| --- | --- |
| `<CR>` | `gh pr checkout` the PR and close the list. `:BranchDiff` / `:BranchCommits` in fugitive-extras review it. |
| `/` | Filter the list as you type (see below). |
| `t` | Its review threads, as `:Thread` (see below). |
| `o` | Open the PR in the browser. |
| `r` | Refresh. |
| `q` | Close (`:q` too). |

`:MergedPRs [count]` is the same list for merged pull requests (not those
closed unmerged), most recently merged first (default 50, at most 100), to
look up what was done and why. Its last two columns are the merge commit
(the squash commit, for a squash merge) and how long ago it was merged.
`/`, `t`, `o`, `r` and `q` are as in `:PRs`; `<CR>` opens the merge commit in
fugitive, in the window above, instead of checking the PR out. The commit
must be fetched. The PRs come from the most recently updated merged ones, so
one merged long ago but commented on since can be among them.

Defined only when [gh](https://cli.github.com) is installed.

### Filtering with `/`

`/` starts a filter: what you type shows at the bottom as `/words`, and the
list narrows with each key to the PRs matching it, best match first. It
matches fuzzily on who, title and branch, as fzf does: `fix login` keeps the
PRs where both words match, each anywhere in who, title or branch, its
letters in order but not necessarily together. While you type:

| Key | What it does |
| --- | --- |
| `<CR>` | Stop typing and keep the filter. The list stays narrowed and its keys (`<CR>`, `t`, `o`, …) work on it. |
| `<Esc>` or `<C-c>` | Stop typing and drop what you changed: back to the filter you had before pressing `/` (none, the first time). |
| `<BS>` | Delete the last character. |
| `<C-w>` | Delete the last word. |
| `<C-u>` | Delete the whole filter, so every PR shows again. You are still typing: `<CR>` leaves the list unfiltered. |

While a filter is kept, the heading shows how many PRs match out of how many
were fetched, and the filter, as `(3/20 matching 'login')`. `r` fetches the
PRs again and applies the same filter to them. To remove it, `/`, `<C-u>`,
`<CR>`; to change it, `/` and type on from where it was.

## Review comments

With [vim-review](https://github.com/roumail/vim-review) installed, its review
comments post to the pull request. Checking a PR out from `:PRs` with unsaved
comments warns once; `:CommentsSubmit` warns too. With
[fugitive-extras](https://github.com/roumail/fugitive-extras), comments go on the
branch side of its diffs and are saved per branch.

| Command | What it does |
| --- | --- |
| `:CommentsSubmit [number]` | Post the comments as one **pending** review of `HEAD` on the branch's PR, or PR `number`, through `gh api`. Only you see it until you submit it on GitHub. Refused while any comment's lines are gone (`W` in `:Comments`, see vim-review's anchors). Defined only when `gh` is installed. |

The review is of the commit you read: `HEAD`, so check the PR out (`:PRs`,
`<CR>`) to review it. If the author pushes more before you submit, the
comments stay on that commit, as on GitHub. Comments on a file changed since
`HEAD` are refused, since their lines aren't its; commit or stash first. When
`HEAD` isn't in the PR (unpushed, or rebased), the review is of the PR's head
instead, if the commented files are the same there, else it is refused.
Comments on lines outside the PR's diff (more than 3 lines from a change, as
GitHub shows it), or on a range across two of its hunks, are named and the
review is not sent, since GitHub rejects the whole review for one of them.

## Review threads

`:Thread [number]` lists the review threads on the branch's PR, or PR
`number`, with their conversations, in a window at the bottom, so you can
read and answer replies to your comments without the GitHub UI. Each thread
is one line: its file and line (`a.py:18-20`), its state, how many comments it
has and the start of the last one, so `j`/`k` go from thread to thread. `=`
opens a thread to its conversation, each comment's author, age and text, and
closes it again, as fugitive's `=` does a file's diff; opened threads stay
open on `r`. `pending` marks a comment of a review you haven't submitted,
which only you see. The heading counts the open threads and those that are **your
turn**: open, with someone else's comment last. Resolved threads are hidden
until `u`. Doesn't need vim-review.

`:Threads` is the same list for the threads you're in across the repo's open
PRs: those with a comment of yours, and every thread on a PR you opened. Each
PR's threads are under a line with its number, branch and title.

| Key | What it does |
| --- | --- |
| `<CR>` | Open the file at the thread's line, in the window above: from the work tree when the PR is the branch checked out, else as of the PR's last commit. An **outdated** thread (its lines changed since) opens the file as of the commit it was made on. Commits must be fetched. |
| `=` | Open the thread to its conversation, or close it to one line. |
| `x` | Resolve the thread, or unresolve a resolved one. |
| `u` | Show or hide resolved threads. |
| `o` | Open the thread's PR in the browser. |
| `r` | Refresh. |
| `q` | Close (`:q` too). |

### Replying

Replies are written as [vim-review](https://github.com/roumail/vim-review)'s
comments and [vim-prompts](https://github.com/roumail/vim-prompts)' asks are:
on the command line, or in a draft when they are longer. In a thread list, on
a thread's line:

| Command | What it does |
| --- | --- |
| `:Reply [text]` | Post `text` as a reply to the thread; prompts unless it is given. Leaving the prompt with `<Esc>` keeps what you typed: `:Reply` or `:ReplyDraft` on the same thread goes on from it. |
| `:ReplyDraft [text]` | Write the reply in a markdown buffer above the list (`g:gh_extras_reply_height`, default `g:review_comment_height`, else 10), starting with `text` if given, else with what you left at the `:Reply` prompt on that thread. A [vim-draft](https://github.com/roumail/vim-draft) draft: `:w` saves it, closing it (`:wq`, or `:q` after `:w`) posts what was last saved, and an empty one or `:q!` before any `:w` posts nothing. |

If posting fails, the reply's text is in the unnamed register. While you have
a pending review on the PR, GitHub adds the reply to it instead, and says so.

To take a reply you're typing to a draft, change `Reply` to `ReplyDraft` on
the command line (`<C-b>` goes to its start) and press Enter. Two `<Plug>`
mappings bind them to keys, the same as vim-review's, say:
`<Plug>(gh-extras-reply)` leaves `:Reply ` on the command line to finish, and
`<Plug>(gh-extras-reply-draft)` is `:ReplyDraft`.

```vim
autocmd BufEnter gh-extras://thread* nmap <buffer> <leader>cc <Plug>(gh-extras-reply)
autocmd BufEnter gh-extras://thread* nmap <buffer> <leader>cd <Plug>(gh-extras-reply-draft)
```

The first 100 threads of a PR are shown, with the first 100 comments of each;
`:Threads` looks at the 50 most recently updated open PRs, and the first 50
comments of a thread. Comments on the PR's conversation, not on a line, aren't
threads and aren't shown. Defined only when `gh` is installed.

## Install

Requires vim-fugitive and [vim-draft](https://github.com/roumail/vim-draft), the buffer replies are written in. With [vim-requires](https://github.com/roumail/vim-requires),
Vim shows `gh-extras: requires …` at startup when one of them isn't loaded.
Its commands need `gh`, and are left out without it.
`:CommentsSubmit` needs vim-review.

```vim
Plug 'tpope/vim-fugitive'
Plug 'roumail/vim-draft'
Plug 'roumail/vim-review'    " optional: :CommentsSubmit
Plug 'roumail/vim-requires'  " optional: the startup warning
Plug 'roumail/gh-extras'
```
