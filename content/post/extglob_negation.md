+++
title = "bash extglob: Tips for using negation/!()"
date = "2025-04-07"
tags = ["unix", "bash", "shell", "cli"]
description = "How to use bash extglob negation/!() and avoid its pitfalls."
toc = true
+++

# Intro

bash's extglob feature enables some additional pattern-matching syntax and brings globbing capabilities a lot closer to typical popular regular expression dialects. In my experience, though, the only extglob operators I've ever had occasion to use are `@(<pat>|...)`, which matches one of the given subpatterns, and `!(<pat>|...)`, which matches anything except one of the given subpatterns. `@()` is intuitive enough, but in my early experiences with `!()` it didn't always behave as I expected, I didn't find any more about it in the docs, and so I mostly gave up on it except for simple cases where it's the only thing in the pattern. And, based on the answers to [this superuser question](https://superuser.com/questions/210168/how-to-move-files-except-files-with-a-given-suffix-in-bash/1889865#1889865), it seems I'm not alone.

# !() is both non-greedy and can accept the empty string

The key things to realize about `!()` is that it can **accept the empty string** and that unlike the other operators it's **non-greedy**. The combination of these attributes means that unless it's at the end of the pattern you need to be careful to force it to eat some of the haystack, by having the following atom not match the empty string.

For example:

    !(jtor*)  # ok: reject files starting with "jtor"
    !(jtor*)*  # wrong: accepts anything
    !(jtor*)!(*.pdf)  # wrong: equivalent to !(*.pdf)
    !(jtor*).!(*.pdf)  # ok: reject files starting with "jtor" or ending with ".pdf"

Following a `!()` with `*` or another `!()` will always make it accept the empty string. When globbing files, bash tries to match `!()` against as little of the filename as possible, giving it one more character at a time. For each character it:

- checks if the filename can be rejected at this position by testing each subpattern in `!()` against the rest of the haystack
- if it can't be rejected at this position of the haystack, then it checks if the filename can be accepted at this position by checking if the rest of the pattern after `!()` matches the rest of the haystack

So, if you want `!()` to eat more, you have to make the following atom fail at earlier positions in the haystack, and thus `!(jtor*)*.pdf` accepts anything and effectively ignores the `!()`, while with `!(jtor*).pdf` the period is going to fail to match in a filename like `jtorbiak_resume.pdf` until the `!()` subexpression eats `jtorbiak_resume`.

# Use cases

- non-test TypeScript files: `!(*.test).ts`
- without a given prefix or suffix: `!(jtor*).!(*.pdf)`
- without either substring: `!(*italic*|*thin*)`
- directories that don't start with given prefix: `!(dir*)/`
    - Sadly, it doesn't seem like you can use a trailing `/` to match only dirs inside of `!()`.
- with none of these extensions: `!(*.svg|*.gp|*.png)`
- with no extension: `!(*.*)`
- with no extension and without some prefix: `!(*.*|jtor*)`

A particularly neat but less-readable use of `!()` is to filter out a subset of a glob by nesting another `!()`. For example, to find files with an extension but that also don't have some prefix, we can do `!(!(*.*)|jtor*)`. The double-negative is awkward, but I find it's not so bad if I read it like: exclude files without an extension or that start with "jtor".

# Performance and other options

While extglob is convenient for interactive use, I would generally avoid using it in scripts since it's not enabled by default and it's more likely to be confusing for others. Also, it's not well-suited for dealing with lots of files since it produces filenames on the command-line, and the max length of a command line isn't huge---it's only a couple megabytes on my system. And, its performance is poor compared to other options. Some regex engines are optimized such that they have linear time complexity as the haystack scales, by trading off memory to construct a DFA or by doing a Thompson simulation on an NFA (see [Regular Expression Matching Can Be Simple And Fast](https://swtch.com/~rsc/regexp/regexp1.html)), but extglob in bash is implemented in a simple recursive way and `!()` is always going to multiply the amount of backtracking that the rest of the pattern needs to do by the number of characters that it needs to eat. Using `find`/`fd` or filtering an overly-accepting glob with a for-loop are often better options.

I was curious about what scale the performance of globbing could become an issue at. For finding files without extensions in my home directory, looking at ~100k files and matching 33k of them, using `find` is noticeably faster. I'm explicitly pruning dot-dirs from the find command since the glob is implicitly doing so.

    ~$ time find . -name ".?*" -prune -o -not -name "*.*" -print | wc -l
    32911

    real    0m0.149s
    user    0m0.053s
    sys     0m0.099s

    ~$ time printf '%s\n' **/!(*.*) | wc -l
    32911

    real    0m0.568s
    user    0m0.133s
    sys     0m0.447s

# Appendix: bash source code

The code for extglob is in the bash repo in `lib/glob/sm_loop.c`. There's a lot of indirection around `sm_loop.c`, since it gets included by `smatch.c` twice, with different preprocessor macro definitions for single and multi-byte characters.

GMATCH and EXTMATCH are mutually recursive, with GMATCH asking EXTMATCH to handle any extglob subexpressions, and EXTMATCH then asking GMATCH to check if each subpattern in an extglob subexpression matches a substring of the haystack. Note that in the outer loop for `!()` here, `srest` iterates from `s` (rest of the haystack) to `se` (end of the haystack) and  GMATCH is asked to check if the subpattern matches from `srest` (EXTMATCH's new idea of the rest of the haystack) to `s`, so on the first iteration it's going to be checking the empty string from `s..s`.

```
// In EXTMATCH(), from sm_loop.c
case '!':           /* match anything *except* one of the patterns */
  for (srest = s; srest <= se; srest++)
    {
      m1 = 0;
      for (psub = p + 1; ; psub = pnext)
        {
          pnext = PATSCAN (psub, pe, L('|'));
          /* If one of the patterns matches, just bail immediately. */
          if (m1 = (GMATCH (s, srest, psub, pnext - 1, NULL, flags) == 0))
            break;
          if (pnext == prest)
            break;
        }
      ...
      if (m1 == 0 && GMATCH (srest, se, prest, pe, NULL, xflags) == 0)
        return (0);
    }
  return (FNM_NOMATCH);
```

## Compiling the test harness in `glob.c`

If you need to convince yourself that extglob works how you think it does, you can compile bash with `DEBUG_MATCHING` defined to get debug input whenever `GMATCH` or `EXTMATCH` are called. You could use bash as a shell with `DEBUG_MATCHING` defined but that resulted in a lot of debug messages that I didn't want, so I used the little test harness in `glob.c`, which just prints the results of matching the patterns given on the command line with the contents of the current directory. `glob.c` depends on a lot of the same stuff that bash itself does, so it's a lot easier to compile it in the same way that you would `bash` instead of trying to isolate it. Here's what worked for me.

- define `DEBUG_MATCHING` by giving `CFLAGS` to configure via an environment variable:

    $ CFLAGS='-g -O2 -DDEBUG_MATCHING' ./configure

- Comment out `main()` in `shell.c`, and uncomment `main()` in `glob.c`
- fix iteration over the matched values in `main()` in `glob.c` by using a different loop variable, since `i` is already being used to iterate over `argv`

Then, run `make` and maybe `cp bash glob` to give the binary a more accurate name. Then it can be run like:

    $ ./glob 'g!(lob)'
    ...
    gmatch: string = general.h; se =
    gmatch: pattern = g!(lob); pe =
    extmatch: xc = !
    extmatch: s = eneral.h; se =
    extmatch: p = (lob); pe =
    extmatch: flags = 33
    gmatch: string = eneral.h; se = eneral.h
    ...
