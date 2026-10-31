# git-extras

Additions to [vim-fugitive](https://github.com/tpope/vim-fugitive): review a
branch the way a pull request shows it, stage hunks in a vertical diff, list
open pull requests and answer their review threads. With
[vim-review](https://github.com/roumail/vim-review), its review comments go on
the branch, are saved per branch and post to the pull request.

"Main" is the repo's default branch: `origin/HEAD`, else `origin/main`,
`origin/master`, `main` or `master`, resolved per repo when a command runs.
Diffs are against the **merge-base** of `HEAD` and main, so they show only
what this branch changes, not what landed on main since it forked. They
include uncommitted changes.

The `:Branch*` commands show the branch like a PR's tabs on GitHub: its
changed files as diffs, and its commits. They take a
branch, local or remote, to review it without checking it out:
`:BranchDiff origin/feature`.
Diffs are then from that branch's merge-base with main to its last commit.
`<Tab>` completes branches, most recent first. Run `:Git fetch` first to see
new remote branches.

| Command | `<Plug>` mapping | What it does |
| --- | --- | --- |
| `:DiffThis` | `<Plug>(git-extras-diff-this)` | `:Gvdiffsplit`: index on the left, working tree on the right. `dp` on a hunk in the working tree stages it, `do` in the index unstages it; `:w` the index buffer to keep it. |
| `:DiffThis!` | `<Plug>(git-extras-diff-main)` | The current file at the merge-base on the left, working tree on the right: what the branch changes in it. |
| `:BranchDiff [branch]` | `<Plug>(git-extras-branch-diff)` | One tab per changed file, each already a diff against the merge-base (`:Git difftool -y`), listed in `:Compares`. |
| `:BranchCommits [branch] [args]` | `<Plug>(git-extras-branch-commits)` | Commits on the branch that main lacks (`:Git log base..branch`). `<CR>` on a commit opens it. Extra args go to `git log`, e.g. `:BranchCommits --stat` or `:BranchCommits -- %`. |
| `:DiffClose [name]` | `<Plug>(git-extras-diff-close)` | Close the tabs of a `:BranchDiff` comparison: `name` (`<Tab>` completes names), else the one this tab is in. From one of its tabs, go back to the window `:BranchDiff` was run from. It stays in `:Compares`; a tab with unsaved changes stays open. Outside a comparison, close the `fugitive://` windows in this tab and `:diffoff!`. |
| `:Compares` | `<Plug>(git-extras-compares)` | The comparisons `:BranchDiff` opened, newest first (see below). |

Reviewing a PR: check it out (`gh pr checkout`), then `:BranchDiff` and
`:BranchCommits`.

## Comparisons

Each `:BranchDiff` is kept as a comparison, as in GitLens' Search & Compare:
named for the branch (the current branch's name without one), with the
merge-base it diffed against. Its tabs carry its name, so closing the files
that raise no questions leaves the ones that do, and
[vim-prompts](https://github.com/roumail/vim-prompts) can send those with
`#diff_pairs:<name>`. A comparison stays listed until you remove it, even
with all its tabs closed, for the rest of the Vim session; another
`:BranchDiff` of the same branch replaces it.

`:Compares` lists them in a window at the bottom: name, `base..head` (`work tree`
when uncommitted changes are in it), files, how many of its tabs are open,
and age.

| Key | Action |
| --- | --- |
| `<CR>` | Close the list and open all its files again, in new tabs, against the same merge-base. `:BranchDiff` again to diff against a new one. |
| `d` | Remove it from the list. Its tabs stay open. To close them too, run `:DiffClose <name>` before removing it. |
| `r` | Refresh. |
| `q` | Close (`:q` too: the list has its own window). |

## Open pull requests

`:PRs [count]` lists the repo's open pull requests, most recently updated first
(default 20), in a window at the bottom, under a line of column headings:
number, who opened it, title, branch, review state (`draft`, `approved`,
`changes`, `review`, or `-`) and age.

Who opened it is their login, or a readable name for it from a file of
`name:login` lines (`Mira:mira-dev`, logins in any case), read on each refresh.

```vim
let g:git_extras_pr_authors = '~/.config/gh-pr-authors.txt'  " the default
```

| Key | What it does |
| --- | --- |
| `<CR>` | `gh pr checkout` the PR and close the list. `:BranchDiff` / `:BranchCommits` review it. |
| `/` | Filter as you type, fuzzily on who, title and branch (space-separated words each match, best match first). `<CR>` keeps the filter, `<Esc>` puts the last one back, `<C-u>` clears it. It stays on `r`. |
| `t` | Its review threads, as `:Thread` (see below). |
| `o` | Open the PR in the browser. |
| `r` | Refresh. |
| `q` | Close (`:q` too). |

Defined only when [gh](https://cli.github.com) is installed.

## Review comments

With [vim-review](https://github.com/roumail/vim-review) installed, its review
comments (`:Comment`, `:Comments`, `:CommentsSave`, `:CommentsLoad`) work with
git:

- A comment goes on a file in the work tree or on the branch side of a diff;
  the merge-base side is refused. Paths are relative to the repo root.
- Saves without a file name are per branch and time,
  `vim-review/<branch>/<YYYYmmdd-HHMMSS>.txt` in the git dir, so they
  are never committed and reviews of different branches stay apart.
  `:CommentsLoad` loads the current branch's latest.
- Switching branches with unsaved comments (`:Git checkout`, `:PRs`) warns
  once; `:Comment` and `:CommentsSubmit` warn too. Nothing is cleared.

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
| `a` | Reply in a markdown buffer above the list, a [vim-draft](https://github.com/roumail/vim-draft) draft: `:w` saves it, closing it (`:wq`, or `:q` after `:w`) posts what was last saved, and an empty one or `:q!` before any `:w` posts nothing. If posting fails, the reply's text is in the unnamed register. While you have a pending review on the PR, GitHub adds the reply to it instead, and says so. |
| `x` | Resolve the thread, or unresolve a resolved one. |
| `u` | Show or hide resolved threads. |
| `o` | Open the thread's PR in the browser. |
| `r` | Refresh. |
| `q` | Close (`:q` too). |

The first 100 threads of a PR are shown, with the first 100 comments of each;
`:Threads` looks at the 50 most recently updated open PRs, and the first 50
comments of a thread. Comments on the PR's conversation, not on a line, aren't
threads and aren't shown. Defined only when `gh` is installed.

No keys are bound; bind the `<Plug>` mappings yourself, for example:

```vim
nmap <leader>cd <Plug>(git-extras-diff-main)
nmap <leader>cl <Plug>(git-extras-branch-commits)
```

## For other plugins

| Function | What it does |
| --- | --- |
| `git_extras#main_ref()` | Main as a ref (`origin/main`, `main`, …) in the current buffer's repo, or `''`. |
| `git_extras#compares#list([gitdir])` | The comparisons in the repo at `gitdir` (default: the current buffer's), newest first, as `{name, base, head, files, time, tabs}`: `head` is `''` for the work tree, `tabs` the tab numbers still showing it. |

## Install

Requires vim-fugitive and [vim-draft](https://github.com/roumail/vim-draft), the buffer replies are written in. With [vim-requires](https://github.com/roumail/vim-requires),
Vim shows `git-extras: requires …` at startup when one of them isn't loaded.
`:PRs`, `:Thread`, `:Threads` and `:CommentsSubmit` also need `gh`, and are left out without it.
Review comments need vim-review.

```vim
Plug 'tpope/vim-fugitive'
Plug 'roumail/vim-draft'
Plug 'roumail/vim-review'   " optional: review comments
Plug 'roumail/vim-requires'  " optional: the startup warning
Plug 'roumail/git-extras'
```
