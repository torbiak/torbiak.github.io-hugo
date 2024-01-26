+++
title = "Using the same colors for the terminal and Vim"
date = "2024-01-25"
aliases = ['choosing_terminal_colors']
tags = ["terminal", "vim", "color"]
description = "How I chose readable colors for the terminal and configured Vim to use them."
toc = true
+++

In short, I've settled on a dark 4-bit terminal palette that is readable for the default and black background colors and use other techniques to workaround unreadable foreground/background combinations, which are mostly when two relatively light colors are put together. I do `:set t_Co = 16` in my vimrc so `colortemplate`-based themes use the terminal palette instead of the absolute 8-bit color model, and use autocommands to modify Vim highlight groups that colorthemes often set to an unreadable combination of my colors.

Warning, I just learned a lot of the stuff in this post, and it's difficult to make definitive statements about terminals due to their long history and multitude of implementations, so I bet I'm kinda wrong or at least not-technically-correct about a lot of this. Don't trust me too much. Also, I'm writing this from a perspective of using classic Vim on Linux.

# Motivation

My primary goal with terminal colors is for text to be readable, with a medium amount of contrast for the most common combinations of foreground and background colors. Years ago I remember often needing to switch Vim colorthemes or turn off syntax highlighting to avoid some highlight groups from being unreadable for certain filetypes or when I was doing a diff, which was a pain. And to save effort, if I come up with colors that are comfortable for me, I'd like to be able to use them in my most commonly used programs; at the very least in the shell and Vim.

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

To understand how the bold/bright colors are used, we need to get into the weeds a bit. The related ANSI/ECMA/ISO standards from the 1970s don't say much on how to implement SGR 1, the "bold" escape sequence, describing it as "BOLD OR INCREASED INTENSITY", so a common approach is for terminals to both use a bolder font as well as to change the foreground to the corresponding bright color, and in some terminals this is the only way to access the bright colors. Later terminals introduced the non-standard escape sequences SGR 90-97 and SGR 100-107 to use the bright colors independently of setting bold; xterm supports these, and for a long time xterm was both popular and the reference implementation of a terminal emulator for the X Window System, and so my impression is that most modern terminals try to be xterm-compatible, to some extent, and also support them. When I [queried terminfo](/post//choosing_terminal_colors/terms_have_bright_bg.sh) with `tput -T"${term:?}" setab`, the popular terminals that I could think of (and that also exist in terminfo) apparently support them too, including: konsole, kitty, alacritty, st, and VTE-based terminals like GNOME, xfce, guake, sakura, and terminator.

# Choosing colors

There's a million ways to design a color scheme, but I went with [4bit Terminal Color Scheme Designer](https://ciembor.github.io/4bit/#), which I'll abbreviate as 4TCSD. It doesn't let you control everything, but it is great for quickly choosing some colors that are collectively cohesive and individually still have the intended meaning/symbolism: for example, errors are often displayed in red, so I want my red to be red enough to convey connotations of danger.

<img src="/post/choosing_terminal_colors/4bit_scheme.png" alt="4bit colorscheme" width="800" />

There's also [terminal.sexy](https://terminal.sexy), which is very flexible, has lots of preview facilities, included themes, and export formats. terminal.sexy is good for tweaking individual colors, but note that while it shows bright colors in the preview templates it doesn't bold the font, so with an imported scheme from 4TCSD the bright colors probably won't look quite how you'd expect. Still, using the `/misc/rows` and `/misc/columns` templates to preview the colors can help stay true to the color names while also quickly checking readability for various foreground/background combinations:

<img src="/post/choosing_terminal_colors/terminal_sexy_templates.png" alt="terminal.sexy templates for checking readability and color trueness" width="800" />

Another thing you'll notice if you import a theme from 4TCSD into terminal.sexy is that all the bright colors are the same as the corresponding normal ones, except for black and white. This has worked out pretty well for me, presumably because I use builtin Vim themes, which rarely use bright colors without also setting bold, but I bet there's lots of themes that are designed with the assumption that the bright and normal colors will be different.

It doesn't seem possible to have every foreground color be readable on every background color, so for a dark theme I tried to optimize having the foreground colors be readable on the default and black background colors while also keeping the constrast somewhere in the middle. If programs define funky color combos like yellow on green, I'm resigned to working around that as needed by choosing alternate program-specific themes or disabling color for them.

I ended up with something like the image above. Unfortunately, 4TCSD doesn't support importing themes, so recreating something you've made before can be a challenge.

# Configuring the terminal

Changing the color palette is different for each terminal. My terminal's config format wasn't supported by 4TCSD so I munged one of the other formats into what I needed, but you could also export for xterm and import that as Xresources into [terminal.sexy](https://terminal.sexy), which supports different export formats than 4TCSD.

# Configuring Vim

Back in Vim v7.0, the builtin colorthemes used color names from `:help cterm-colors` for color terminals, which are interpreted differently depending on `t_Co` (explained shortly), and 24-bit color for the GUI. And in Dec 2023 (Vim v9.1) the builtin themes were rewritten using the [colortemplate plugin](https://github.com/lifepillar/vim-colortemplate), and now each has specific support for 256, 16, 8, and 2 colors. The builtin themes still choose how many colors to use based on the `t_Co` option, which represents the max number of colors that the terminal supports (up to 256) and is retrieved from the terminfo db (see the `Co` capability in `terminfo(5)`) based on the value of the `TERM` environment variable, but you can override `t_Co` in your vimrc to get themes to use a lower-fidelity color model if desired. (True color, on the other hand, [is advertised by terminals in various ways](https://github.com/termstandard/colors#checking-for-colorterm) and can be enabled in `vim` with `:set termguicolors`.) So, the easiest way to get Vim to use the terminal's 4-bit palette is to do `:set t_Co = 16` in your vimrc.

When testing out Vim color themes I'd recommend using `:highlight` to check highlight groups to identify unreadable highlight groups early. The most important ones are on the first page, and most other highlight groups will link to them.

There's a few highlight groups that I dislike in a lot of the builtin themes. First, I almost always want my default background color to be used, so I override `Normal` to have `ctermbg=NONE` for dark 4-bit backgrounds. In the snippet below, the `ColorScheme` event fires after any (`*`) colorscheme is loaded. See `:help colorscheme-override` for more info on overriding colorschemes, and you may need to read the docs for autocommands as well depending on your familiarity with them.

In my vimrc:

    augroup color_mods
        au!
        " Use the default background color for dark 4-bit schemes.
        au ColorScheme * {
            if str2nr(&t_Co) == 16 and &background ==# 'dark'
                hi Normal ctermbg=NONE
            endif
        }
        ...
    augroup END

One downside to using terminal colors is that themes on the opposite side of the light/dark spectrum probably won't work well . My terminal colors don't work well with light colorschemes, so if did want to use a light theme I'd either `:set t_Co = 256` or choose a light set of terminal colors.

Second, I find the diff highlight groups to be unreadable for a lot of themes. A quick way to mitigate this is to set `:syntax off`, and depending on how busy the syntax highlighting is for changed lines that might be necessary, but I've been able to avoid doing so lately by overriding the relevant highlight groups, using a black background for `DiffChange` instead of something more colorful:

    augroup color_mods
        au!

        ...

        au ColorScheme * hi DiffAdd ctermfg=DarkGreen ctermbg=Black
        au ColorScheme * hi DiffChange ctermfg=DarkYellow ctermbg=Black
        au ColorScheme * hi DiffDelete ctermfg=DarkRed ctermbg=Black
        au ColorScheme * hi DiffText ctermfg=DarkYellow ctermbg=Blue
    augroup END

Resulting in something like this:

![diff example](/post/choosing_terminal_colors/diff.png)

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

tput_demo.sh:

    #!/bin/bash
    set -eu
    setaf=$(tput setaf)
    set_fg_red=$(tput setaf 1)
    set_fg_bright_red=$(tput setaf 9)
    clear_attrs=$(tput sgr0)

    declare -p setaf set_fg_red set_fg_bright_red clear_attrs
    echo "${set_fg_red}hi ${set_fg_bright_red}there ${clear_attrs}again"

And in a terminal with different colors defined for red and bright red:

![tput demo](/post/choosing_terminal_colors/tput_demo.png)

# See also

- [Consistent terminal colors with 16-ANSI-color Vim themes](https://jeffkreeftmeijer.com/vim-16-color/) 
discusses a different approach: instead of setting `t_Co`, Jeff wrote a colortheme that uses 4-bit color numbers directly and redefines all the highlight groups that are defined by default. Vim maps the `cterm-colors` names to numbers based on `t_Co`, and the default colortheme is specified in terms of color names, so if `t_Co == 256` then some of the highlight groups will start out with colors in the 8-bit space from 16-255. I think there could be a small downside to this approach in that non-ANSI terminals won't display the colors in the theme as intended, due to the different number-to-color mapping.
