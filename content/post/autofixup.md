+++
title = "Absorb changes across a topic branch in git"
date = "2017-06-04"
tags = ["git", "perl", "vcs"]
description = "Use git-autofixup to automatically create fixup! commits for a topic branch."
draft = true
+++

## Motivation: tedious fixups

Here's the situation. I'm working on a feature and end up with a chain of commits that depend on each other. It'd be easier for me as the author to put all the work in a single commit, but I like telling stories with my commits to (hopefully) make reviewing the branch easier and the history more meaningful in general. Anyway, the review goes back and forth for a while, motivating a bunch of small edits that are logically most connected to various commits. I commit these edits separately and then squash/fixup them all with an interactive rebase. Now, assigning changes to commits representing logical groups of changes was fun/challenging the first time, but assigning these small edits borne of review feedback is nearly a mechanical process of scanning through the list of topic branch commits and copy-pasting SHAs. [Or, more conveniently, using `git commit --fixup=:/<regex>`, although I haven't thought to do that until recently.]

Personal and team git workflows apparently vary wildly, so not everyone has dealt with this situation, but I've encountered it with enough regularity that when I read the description of Facebook's [`hg absorb`](https://bitbucket.org/facebook/hg-experimental/src/abee33554ccf744c852b14876d1d2069e3fe22d2/hgext3rd/absorb/__init__.py?at=default&fileviewer=file-view-default) command in these [Mercurial sprint notes](https://groups.google.com/forum/#!topic/mozilla.dev.version-control/nh4fITFlEMk) I was super envious. To cure my envy I wrote [`git-autofixup`](https://githup.com/torbiak/git-autofixup).

## How it works

`git-autofixup` parses hunks of changes in the working directory out of `git diff` output and uses `git blame` to assign those hunks to commits in `<revision>..HEAD`, which will typically represent a topic branch, and then creates fixup commits to be used with `git rebase --interactive --autosquash`.

By default a hunk will be included in a fixup commit if the hunk's context shows there's an unambiguous target topic branch commit. There are two situations where a target commit is considered unambiguous:
    
1. When it's the only topic branch commit the hunk is near. More precisely, when it's the only topic branch commit appearing in the blame output of all the hunk's context lines.

2. It's blamed for all the lines that the hunk changed, even if changes from other topic branch commits are nearby. More precisely, it's blamed for all the removed lines and at least one of the context lines adjacent to added lines, and no context lines adjacent to added lines are blamed on any other topic branch commits.

Slightly stricter assignment criteria are also available for when you're untangling fixups from changes for a new commit: see the description of the `--strict` option in the `--help`.

## Example

`git-autofixup` is most useful on big projects, in big teams, on long-lived topic branches, but I've tried to concoct a small example that motivates its use. Say we have a little python library that for whatever reason transforms a given name so the letters of the last word of the name alternate between upper and lower case:

    def last_name_alternating_case(name):
        """Return name, but with the last word in aLtErNaTiNg case."""
        words = name.split()
        letters = list(words[-1])
        for (i, char) in enumerate(letters):
            if i % 2 == 0:
                letters[i] = char.lower()
            else:
                letters[i] = char.upper()
        words[-1] = ''.join(letters)
        return ' '.join(words)

A new function is required that alternates the case of the letters in every other word of a given string, so we start a topic branch and have it track `master`. Before we start writing `odd_words_alternate_case`, though, we realize some of the logic needed can be factored out of `last_name_alternating_case`. So we do that and make a commit with the summary `Factor out alternating_case function`. The file is now:

    def last_name_alternating_case(name):
        """Return name, but with the last word in aLtErNaTiNg case."""
        words = name.split()
        words[-1] = alternating_case(words[-1])
        return ' '.join(words)

    def alternating_case(s):
        letters = list(s)
        for (i, char) in enumerate(letters):
            if i % 2 == 0:
                letters[i] = char.upper()
            else:
                letters[i] = char.lower()
        return ''.join(letters)

Now we're ready to write `odd_words_alternate_case` using `alternating_case`, and commit it as `Add odd_words_alternating_case`:

    def odd_words_alternating_case(s):
        """Returns the string with alternating words in alternating case."""
        words = s.split()
        for (i, word) in enumerate(words):
            if i % 2 == 0:
                continue
            words[i] = alternating_case(word)
        return ' '.join(words)

Looking the code over, we realize we want to give `alternating_case` a docstring, change the tense/mood of the `odd_words_alternating_case` docstring so it's consistent with `last_name_alternating_case`, and we decide the first character of alternating-case words should be uppercase. Here's the diff of these unstaged changes:

    diff --git a/ex.py b/ex.py
    index 2ed7e63..2a5e73b 100644
    --- a/ex.py
    +++ b/ex.py
    @@ -7,2 +7,3 @@ def last_name_alternating_case(name):
     def alternating_case(s):
    +    """Return s with its characters in aLtErNaTiNg case."""
         letters = list(s)
    @@ -10,5 +11,5 @@ def alternating_case(s):
             if i % 2 == 0:
    -            letters[i] = char.upper()
    -        else:
                 letters[i] = char.lower()
    +        else:
    +            letters[i] = char.upper()
         return ''.join(letters)
    @@ -16,3 +17,3 @@ def alternating_case(s):
     def odd_words_alternating_case(s):
    -    """Returns the string with alternating words in alternating case."""
    +    """Return s with odd words in alternating case."""
         words = s.split()

We'd like to squash these changes into the previous two commits. In this particular instance it'd be quite easy to do with two rounds of `git add --patch` followed by `git commit --fixup=:/<regex>`. but if the topic branch had more commits and we were fixing up more areas this process would get tedious. Let's see what `git-autofixup` does with it:

    $ ../git-autofixup -vv @{upstream}
    ex.py @@ -5,16 +5,17 @@ has multiple targets
    656a790f|   5|    return ' '.join(words)    |     return ' '.join(words)
    656a790f|   6|                              |
    656a790f|   7|def alternating_case(s):      | def alternating_case(s):
            |    |                              |+    """Return s with its char
    656a790f|   8|    letters = list(s)         |     letters = list(s)
    ^       |   9|    for (i, char) in enumerate|     for (i, char) in enumerat
    ^       |  10|        if i % 2 == 0:        |         if i % 2 == 0:
    ^       |  11|            letters[i] = char.|-            letters[i] = char
    656a790f|  12|        else:                 |-        else:
    656a790f|  13|            letters[i] = char.|             letters[i] = char
            |    |                              |+        else:
            |    |                              |+            letters[i] = char
    656a790f|  14|    return ''.join(letters)   |     return ''.join(letters)
    5be3a3b9|  15|                              |
    5be3a3b9|  16|def odd_words_alternating_case| def odd_words_alternating_cas
    5be3a3b9|  17|    """Returns the string with|-    """Returns the string wit
            |    |                              |+    """Return s with odd word
    5be3a3b9|  18|    words = s.split()         |     words = s.split()
    5be3a3b9|  19|    for (i, word) in enumerate|     for (i, word) in enumerat
    5be3a3b9|  20|        if i % 2 == 0:        |         if i % 2 == 0:


We're using high verbosity (`-vv`) so that the "blamediff" gets printed and we can see how the hunks are being handled. Our changes are close enough together that they all get put into the same hunk with the default number of diff context lines (3), and then that single hunk is related to both of our topic branch commits. When we reduce the number of context lines to get more hunks the unstaged changes are isolated enough to be assigned to their respective commits and two `fixup!` commits are created:

    $ git-autofixup --context=1 -vv @{upstream}
    ex.py @@ -7,2 +7,3 @@ fixes 656a790f Factor out alternating_case function
    656a790f|   7|def alternating_case(s):      | def alternating_case(s):
            |    |                              |+    """Return s with its char
    656a790f|   8|    letters = list(s)         |     letters = list(s)

    ex.py @@ -10,5 +11,5 @@ fixes 656a790f Factor out alternating_case function
    ^       |  10|        if i % 2 == 0:        |         if i % 2 == 0:
    ^       |  11|            letters[i] = char.|-            letters[i] = char
    656a790f|  12|        else:                 |-        else:
    656a790f|  13|            letters[i] = char.|             letters[i] = char
            |    |                              |+        else:
            |    |                              |+            letters[i] = char
    656a790f|  14|    return ''.join(letters)   |     return ''.join(letters)

    ex.py @@ -16,3 +17,3 @@ fixes 5be3a3b9 Add odd_word_alternating_case function
    5be3a3b9|  16|def odd_words_alternating_case| def odd_words_alternating_cas
    5be3a3b9|  17|    """Returns the string with|-    """Returns the string wit
            |    |                              |+    """Return s with odd word
    5be3a3b9|  18|    words = s.split()         |     words = s.split()

    [topic 44cadf7] fixup! Add odd_word_alternating_case function
     1 file changed, 1 insertion(+), 1 deletion(-)
    [topic bde4ca5] fixup! Factor out alternating_case function
     1 file changed, 3 insertions(+), 2 deletions(-)


Finally, we do a `git rebase --interactive --autosquash` and see git has set the fixup commits to be squashed into their targets:

    pick 656a790 Factor out alternating_case function
    fixup cfa466e fixup! Factor out alternating_case function
    pick 5be3a3b Add odd_word_alternating_case function
    fixup 1a6c084 fixup! Add odd_word_alternating_case function

## Where to get it

Check it out on [GitHub](https://github.com/torbiak/git-autofixup) or the [CPAN](https://metacpan.org/pod/distribution/App-Git-Autofixup/git-autofixup). It can be installed using a CPAN client or by simply downloading the self-contained script, [`git-autofixup`](https://raw.githubusercontent.com/torbiak/git-autofixup/master/git-autofixup), to a directory in `PATH`.
