+++
title = "Using the same colors for the terminal and Vim"
date = "2024-01-25"
aliases = ['choosing_terminal_colors']
tags = ["terminal", "vim", "color"]
description = "How I chose readable colors for the terminal and configured Vim to use them."
toc = true
last_updated = "2024-02-12"
+++

In short, I've settled on a dark 4-bit terminal palette that is readable for the default and black background colors and use other techniques to workaround unreadable foreground/background combinations, which are mostly when two relatively light colors are put together. I do `:set t_Co=16` in my vimrc so themes that check it use the terminal palette instead of the absolute 8-bit color model, and use autocommands to modify Vim highlight groups that colorschemes often set to an unreadable combination of my colors. And in the end I wrote a basic colorscheme to suit the terminal colors I chose.

Warning, I just learned a lot of the stuff in this post, and it's difficult to make definitive statements about terminals due to their long history and multitude of implementations, so I bet I'm kinda wrong or at least not-technically-correct about a lot of this. Don't trust me too much. Also, I'm writing this from a perspective of using classic Vim on Linux.

# Motivation

My primary goal with terminal colors is for text to be readable, with a medium amount of contrast for the most common combinations of foreground and background colors. Years ago I remember often needing to switch Vim colorschemes or turn off syntax highlighting to avoid some highlight groups from being unreadable for certain filetypes or when I was doing a diff, which was a pain. And to save effort, if I come up with colors that are comfortable for me, I'd like to be able to use them in my most commonly used programs; at the very least in the shell and Vim.

# Choosing a color model

[Wikipedia](https://en.wikipedia.org/wiki/ANSI_escape_code#Colors) has some good information on the color models used in terminals. My impression is that most of the popular terminal emulators now support most of the color models that have been developed. This table isn't exhaustive.

|bits|colors|notes|
|----|------|-----|
|1-bit|2|monochrome|
|3-bit|8|superceded by 4-bit, but its influence remains visible|
|4-bit|16+2|widely supported|
|7-ish?|88|4x4x4 color cube, used mostly by older terminals like rxvt and xterm-88color, [designed to save memory in the X server colormap vs 8-bit color](https://unix.stackexchange.com/a/688348/215497)|
|8-bit|256|[6x6x6 color cube](https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit), typically defined the same as in xterm. Depending on the terminal it can be possible to redefine these colors using escapes or X resources, but generally they're considered to be "absolute"/fixed.|
|24&#8209;bit|lots|"true color", with each of RGB specified from 0-255. Definitely absolute. [Fairly well-supported in terminals](https://github.com/termstandard/colors), but less so in terminal-based programs.|

4-bit color is the obvious choice of color model when designing a custom palette, since it has been widely supported by terminals and terminal-based programs for a long time now, most terminals let you change the colors easily, and picking 18 colors doesn't take too long. With it we can pick a default foreground color, a default background color, 8 normal colors that can always be used for the foreground or backgorund, and 8 bold/bright colors whose use can sometimes be limited to when bold is selected for the foreground, but usually can be used whenever.

To understand how the bold/bright colors are used, we need to get into the weeds a bit. The related ANSI/ECMA/ISO standards from the 1970s don't say much on how to implement SGR 1, the "bold" escape sequence, describing it as "BOLD OR INCREASED INTENSITY", so a common approach is for terminals to both use a bolder font as well as to change the foreground to the corresponding bright color, and in some terminals this is the only way to access the bright colors. Later terminals introduced the non-standard escape sequences SGR 90-97 and SGR 100-107 to use the bright colors independently of setting bold; xterm supports these, and for a long time xterm was both popular and the reference implementation of a terminal emulator for the X Window System, and so my impression is that most modern terminals try to be xterm-compatible, to some extent, and also support them. When I [queried terminfo](#appendix-query-if-bright-background-is-supported) with `tput -T"${term:?}" setab`, the popular terminals that I could think of (and that also exist in terminfo) apparently support them too, including: konsole, kitty, alacritty, st, and VTE-based terminals like GNOME, xfce, guake, sakura, and terminator.

# Choosing colors

There's a million ways to design a color scheme, but I went with [4bit Terminal Color Scheme Designer](https://ciembor.github.io/4bit/#), which I'll abbreviate as 4TCSD. It doesn't let you control everything, but it is great for quickly choosing some colors that are collectively cohesive and individually still have the intended meaning/symbolism: for example, errors are often displayed in red, so I want my red to be red enough to convey connotations of danger. I particularly recommend playing with the "Dye" tab, which adds a color cast to a desired subset of colors, and can have a big effect on how cohesive the theme looks.

<img src="/post/same_colors_in_terminal_and_vim/4bit_scheme.png" alt="4bit colorscheme" width="800" />

There's also [terminal.sexy](https://terminal.sexy), which is very flexible, has lots of preview facilities, included themes, and export formats. terminal.sexy is good for tweaking individual colors, but note that while it shows bright colors in the preview templates it doesn't bold the font, so with an imported scheme from 4TCSD the bright colors probably won't look quite how you'd expect. Still, using the `/misc/rows` and `/misc/columns` templates to preview the colors can help stay true to the color names while also quickly checking readability for various foreground/background combinations:

<img src="/post/same_colors_in_terminal_and_vim/terminal_sexy_templates.png" alt="terminal.sexy templates for checking readability and color trueness" width="800" />

It doesn't seem possible to have every foreground color be readable on every background color, so for a dark theme I tried to optimize having the foreground colors be readable on the default and black background colors while also keeping the constrast somewhere in the middle. If programs define funky color combos like yellow on green, I'm resigned to working around that as needed by choosing alternate program-specific themes or disabling color for them.

I ended up with something like in the image of 4TCSD above. Unfortunately, 4TCSD doesn't support importing themes, so recreating something you've made before can be a challenge.

# Configuring the terminal

Permanently changing the color palette is different for each terminal. My terminal's config format wasn't supported by 4TCSD and I couldn't find any other tools to convert between formats on the command line so I wrote a quick-and-dirty script in Python called [`conv4bit`](https://github.com/torbiak/conv4bit/blob/main/conv4bit.py). Alternatively, terminal.sexy supports different export formats than 4TCSD, so exporting for xterm from 4TCSD and importing that as Xresources in terminal.sexy might be helpful.

A lot of terminals support using xterm-style OSC 4/10/11/12 escapes to change the 4-bit palette on-the-fly, which is especially convenient for trying out and editing themes. I had fun cloning the [Gogh](https://github.com/Gogh-Co/Gogh) repo, applying one of its themes with `conv4bit -ofmt osc "themes/${theme:?}" -`, and then attaching to an existing tmux session to preview the theme in a variety of situations.

# Configuring Vim

Back in Vim v7.0, the builtin colorschemes used color names from `:help cterm-colors` for color terminals, which are interpreted differently depending on `t_Co` (explained shortly), and 24-bit color for the GUI. And in Dec 2023 (Vim v9.1) the builtin themes were rewritten using the [colortemplate plugin](https://github.com/lifepillar/vim-colortemplate), and now each has specific support for 256, 16, 8, and 2 colors. The builtin themes still choose how many colors to use based on the `t_Co` option, which represents the max number of colors that the terminal supports (up to 256) and is retrieved from the terminfo db (see the `Co` capability in `terminfo(5)`) based on the value of the `TERM` environment variable, but you can override `t_Co` in your vimrc to get themes to use a lower-fidelity color model if desired. (24-bit color, on the other hand, [is advertised by terminals in various ways](https://github.com/termstandard/colors#checking-for-colorterm) and can be enabled in `vim` with `:set termguicolors`.) So, the easiest way to get Vim to use the terminal's 4-bit palette is to do `:set t_Co=16` in your vimrc.

When testing out Vim color themes I'd recommend using `:help highlight-groups` to identify unreadable groups early, and `:help group-name` to see the hierarchy of groups commonly used for programming language syntax. Note that most of the default highlight groups have a help entry under `hl-<name>` (eg `hl-DiffAdd`), which describes what it's for. Highlight groups for specific languages will mostly link to the ones defined by default. 

Also, it's quite helpful to see what syntax/highlight group is under the cursor, and the following function can be bound to a key to do that. A simplified description is that it shows the matching and linked syntax groups. The effective highlight group could be different from what `SynGroup()` shows, though, such as when doing a diff, using visual mode, etc.  Note that syntax and highlight group names are kind of shared, and syntax group names can be used with the `:highlight` command to create a corresponding highlight group or link to one, like with `:hi link pythonStatement Statement`, which links the `pythonStatement` syntax group to the `Statement` highlight group.

    function! SynGroup()
        let id = synID(line('.'), col('.'), 1)
        echo synIDattr(id, 'name') . ' -> ' . synIDattr(synIDtrans(id), 'name')
    endfunction

There's a few highlight groups that I dislike in a lot of the builtin themes. I almost always want my default background color to be used, so I override `Normal` to have `ctermbg=NONE` when 4-bit color is being used. It can be tricky to get the search-related groups emphasized enough while also being readable, and striking the right balance really depends on what your terminal colors are. And for diff, putting red/green/yellow on black for removed/added/changed seems to work well compared to using more colorful combinations, assuming black is easily distinguished from the default background color. In the snippet below, the `ColorScheme` event fires after any (`*`) colorscheme is loaded. See `:help colorscheme-override` for more info on overriding colorschemes, and you may need to read the docs for autocommands as well depending on your familiarity with them. With Vim9 script you can put multiple autocommands in curly braces, but I like to keep my vimrc compatible with somewhat older Vim versions too, so I'm defining a function instead. In my vimrc:

    function ModColorScheme()
        " Customize colorscheme when using 4-bit color.
        if str2nr(&t_Co) == 16
            hi Normal ctermfg=NONE ctermbg=NONE

            hi Visual ctermfg=Black ctermbg=Cyan cterm=NONE
            hi Search ctermfg=Red ctermbg=Black cterm=bold
            hi IncSearch ctermfg=White ctermbg=DarkRed cterm=bold

            hi DiffAdd ctermfg=DarkGreen ctermbg=Black cterm=NONE
            hi DiffChange ctermfg=DarkYellow ctermbg=Black cterm=NONE
            hi DiffDelete ctermfg=DarkRed ctermbg=Black cterm=NONE
            hi DiffText ctermfg=Black ctermbg=DarkYellow cterm=bold
        endif
    endfunction
    augroup color_mods
        au!
        au ColorScheme * call ModColorScheme()
    augroup END

For diffs this results in:

![diff example](/post/same_colors_in_terminal_and_vim/diff.png)

One downside to using terminal colors is that themes on the opposite side of the light/dark spectrum probably won't work well . My terminal colors don't work well with light colorschemes, so if did want to use a light theme I'd either use 8 or 24-bit color or choose a light set of terminal colors.

## Vim's cterm-colors

When inspecting Vim colorthemes or highlight groups, it's helpful to know what the color names and numbers mean. As explained at `:help cterm-colors`, Vim uses MS Windows names for colors, which is confusing if you're thinking in terms of the ANSI names. And also, later in the Vim help it's explained that ANSI-style terminals use the NR-8 column of numbers in the table below and add 8 for the bright variants, and this includes xterm, and thus likely also includes most terminals on Linux. Here's the table from `:help cterm-colors`, with a column of ANSI-ish color names added.

    NR-16  NR-8  Vim color name                    ANSI color name
    0      0     Black                             black
    1      4     DarkBlue                          blue
    2      2     DarkGreen                         green
    3      6     DarkCyan                          cyan
    4      1     DarkRed                           red
    5      5     DarkMagenta                       magenta
    6      3     Brown, DarkYellow                 yellow
    7      7     LightGray, LightGrey, Gray, Grey  white
    8      0*    DarkGray, DarkGrey                bright black
    9      4*    Blue, LightBlue                   bright blue
    10     2*    Green, LightGreen                 bright green
    11     6*    Cyan, LightCyan                   bright cyan
    12     1*    Red, LightRed                     bright red
    13     5*    Magenta, LightMagenta             bright magenta
    14     3*    Yellow, LightYellow               bright yellow
    15     7*    White                             bright white

Basically, `DarkRed` maps to ANSI red (1), while `LightRed` and `Red` map to ANSI bright red (9), and this pattern holds for all the other colors too except for white and black.

Clearly the number 9 doesn't match the ANSI-style SGR escape sequence to set the foreground to bright red, which is SGR 91. 9 will get translated to the appropriate escape sequence for the terminal during display, likely by [ncurses](https://github.com/mirror/ncurses/blob/master/ncurses/tinfo/lib_tparm.c) in concert with terminfo. For example, the terminfo `setaf` or "Set ANSI Foreground" capability gives a recipe in a simple stack-based programming language (described in `terminfo(5)`) to translate the color number to the right escape sequence for the current terminal, and the `tput` program that comes with ncurses can interpret that recipe.

`tput_demo.sh`:

    #!/bin/bash
    set -eu
    setaf=$(tput setaf)
    set_fg_red=$(tput setaf 1)
    set_fg_bright_red=$(tput setaf 9)
    clear_attrs=$(tput sgr0)

    declare -p setaf set_fg_red set_fg_bright_red clear_attrs
    echo "${set_fg_red}hi ${set_fg_bright_red}there ${clear_attrs}again"

And in a terminal with different colors defined for red and bright red:

![tput demo](/post/same_colors_in_terminal_and_vim/tput_demo.png)

# Writing a Vim colorscheme

I've been pretty happy using the `pablo` or `default` builtin colorschemes along with my set of terminal colors since 2016, but after writing the first version of this post and learning more about how colors and themes work in Vim, I started overriding more and more highlight groups that I wasn't totally happy with until it was obvious that I should just write my own theme. For people writing configurable themes with light and dark variants for multiple color models and both Vim and Neovim it makes sense to script the theme generation, but since I just wanted a 4-bit dark theme for Vim and the palette is already set, I didn't need any indirection and simply modified a list of `:highlight` commands  based on the `default` scheme.

I used [colortemplate](https://github.com/lifepillar/vim-colortemplate) to generate a clone of the `default` theme using its [default_clone.colortemplate](https://github.com/lifepillar/vim-colortemplate/blob/master/templates/default_clone.colortemplate) and then removed almost everything except the header and 4-bit `if s:t_Co >= 16` section, but you could also just take the 4-bit section from any other builtin theme in Vim v9.1+, since they're all generated with colortemplate. Prior to v9.1 some of the builtin themes don't override all of the groups that `default` defines, so they're less useful as templates.

I ended up with [forbit.vim](/post/same_colors_in_terminal_and_vim/forbit.vim), which starts like this:

    <snip header>

    set background=dark
    hi clear
    let g:colors_name = 'forbit'

    hi Normal ctermfg=NONE ctermbg=NONE cterm=NONE
    hi Comment ctermfg=lightblue ctermbg=NONE cterm=NONE
    hi Constant ctermfg=darkmagenta ctermbg=NONE cterm=NONE
    <continues...>

To apply a colorscheme they just get sourced, so you could put it anywhere, but Vim looks for colorschemes in a few locations by default, including `~/.vim/colors`, so after putting it there I could simply run `:colorscheme forbit`.

forbit doesn't pass the `$VIMRUNTIME/colors/tools/check_colors.vim` script, which is recommended for colorschemes that are intended to be shared, but it's good enough for my purposes. The point is to make it easy for me to customize colors as needed, which I wish I had started doing earlier.

# See also

- [Consistent terminal colors with 16-ANSI-color Vim themes](https://jeffkreeftmeijer.com/vim-16-color/)
discusses a different approach: instead of setting `t_Co`, Jeff wrote a colorscheme that uses 4-bit color numbers directly and redefines all the highlight groups that are defined by default. Vim maps the `cterm-colors` names to numbers based on `t_Co`, and the default colorscheme is specified in terms of color names, so if `t_Co == 256` then some of the highlight groups will start out with colors in the 8-bit space from 16-255. I think there could be a small downside to this approach in that non-ANSI terminals won't display the colors in the theme as intended, due to the different number-to-color mapping.
- [Gogh](https://github.com/Gogh-Co/Gogh) has a bunch of 4-bit themes specified in YAML/JSON and includes scripts to install them for various terminals.

# Appendix: query if bright background is supported

    #!/bin/bash
    set -euo pipefail

    terms=(
        terminator
        alacritty
        konsole-256color
        gnome-256color
        kitty
        st-256color
        xterm-256color
        vte-256color
    )
    for t in "${terms[@]}"; do
        setab=$(tput -T"$t" setab) || continue
        # Look for the "then" (%t) part of a conditional which does:
        # - 10: print "10"
        # - %p1: push param1 on the stack
        # - %{8}: push a literal 8 on the stack
        # - %-: pop the top two values and push their difference
        # - %d: pop a value and print it as a int
        [[ "$setab" = *'%t10%p1%{8}%-%d'* ]] && bright_bg=yes || bright_bg=no
        echo "$t $bright_bg"
    done

# Addendum: changelog

## 2024-02-12

- Remove paragraph about 4TCSD themes having the same color for the normal and bright variants; somehow I didn't notice my color lightness sliders were overlapping. Update the 4TCSD screenshot, too.
- Update vimrc snippets to avoid Vim9 script for now.
- Mention better ways to check highlight groups: `:help group-name` and `:help highlight-groups`.
- Add section on writing my own Vim colorscheme.
- Mention `conv4bit`, a script to convert between 4-bit theme formats.
- Move the terminfo querying script into the appendix instead of linking to the file.
