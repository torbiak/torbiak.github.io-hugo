+++
title = "Time-Series Histograms: Gnuplot vs matplotlib"
date = "2017-07-16"
tags = ["data", "visualization", "gnuplot", "python", "perl", "numpy", "matplotlib", "charting", "time"]
description = "A tutorial on creating time-binned histogram charts using Gnuplot and matplotlib, and some of the tradeoffs between the two tools."
toc = true
images = ["/post/histogram_gnuplot_vs_matplotlib/preview.png"]
+++

# Introduction

I wanted to learn a charting tool that is:

- convenient enough to quickly create rough data visualizations without it feeling like an indulgent digression
- fast enough to visualize large datasets, maybe millions of points
- scriptable, so chart source code plays well with version control

Without doing much research on the options I decided to start with the venerable Gnuplot. Data I've needed to analyze at previous jobs have always been time-series, so I chose visualizing my bash history as a practice task. After working through a series of charts of increasing sophistication with Gnuplot I started worrying that other tools might be more convenient, so I replicated my Gnuplot journey with matplotlib. I've been disappointed with the resources I've found for charting time-series data in both Gnuplot and matplotlib, motivating me to share my experience.

In the end my worries were unfounded and I'm actually pretty happy with Gnuplot, especially for quick-and-dirty jobs. matplotlib certainly has some advantages, like having a popular, sensible language like Python as its interface, and possibly being an alternative to R when used along with numpy, but given my weakness to one-liners Gnuplot is difficult to resist. Read on for the details.

# The data

I'm examining my `bash` history to see when I've been most active over the past couple days. To get some data we can set `HISTTIMEFORMAT` so `bash`'s `history` command annotates entries with timestamps:

    $ HISTTIMEFORMAT="%Y-%m-%dT%H:%M:%S " history >shellhist
    $ tail shellhist
    10215  2017-07-01T09:52:36 make dist
    10216  2017-07-01T09:52:40 git tag
    10217  2017-07-01T09:52:44 git tag v0.002003
    10218  2017-07-01T09:52:57 cpan-upload -u TORBIAK App-Git-Autofixup.tar.gz
    10219  2017-07-01T09:53:08 git push
    10220  2017-07-01T09:53:13 git push --tags
    10221  2017-07-01T09:53:31 make realclean
    10222  2017-07-01T09:53:36 rm App-Git-Autofixup-0.002003.tar.gz
    10223  2017-07-01T09:53:38 fg

# Gnuplot

## A rough start: points

To get a rough visualization of when commands were entered we can tell Gnuplot we're dealing with time data on the x-axis by setting `xdata time` and `timefmt` and plot each command as a point, spreading the points across the y-axis at random to make it easier to get a sense of their density. Gnuplot interprets `using 2:(rand(0))` to mean that we're using the second column of `shellhist` for the x-values, and random floats in the interval [0:1] as the y-values. The parentheses around `rand(0)` are necessary to signal that we want to use the value of an expression instead of selecting a column from the data file.[^using]

`shellhist_gp_points.gnuplot`:

    set xdata time
    set timefmt "%Y-%m-%dT%H:%M:%S"
    plot 'shellhist' using 2:(rand(0)) with points

Plot the script using a command like:

    GNUTERM=svg gnuplot shellhist_gp_points.gnuplot >shellhist_gp_points.svg

![shellhist_gp_points.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_gp_points.svg)

## Binning times

The above chart gives a rough idea of when I was executing commands, but it'd be interesting to get more specific and quantify how many commands I was running per hour or minute. To do that we need to put entries in bins, mapping the command timestamps to intervals of the desired length. If we're glancing at the manual we might think that the `histograms` plotting style does what we want, but it doesn't: it expects data to already be binned. We need to bin the data some other way; we could use a different tool or programming language, or we can use the `smooth frequency` modifier for Gnuplot's `using` clause, which adds ups the y-values for each unique x-value encountered.[^smooth] So if we can get the time values as [epoch seconds](https://en.wikipedia.org/wiki/Unix_time), round them to the start of the interval[^leap] they're in, and set the y-values as `1.0`, then `smooth frequency` will add up those ones, creating the needed mapping of interval start times to number of commands executed.

Gnuplot represents times as epoch seconds[^time_repr] and since we've set `timefmt` and `xdata time` we might expect that referencing column 2 in the expression for the x-values would evaluate to epoch seconds, but it actually follows the usual behaviour and evaluates to the first number present in the field, 2017 in our case. We've specified that xdata is time-based, not that column 2 is only to be interpreted as a time. 

    # WRONG. $2 evaluates to 2017, not epoch seconds.
    set xdata time
    set timefmt "%Y-%m-%dT%H:%M:%S"
    binwidth = 3600
    plot 'shellhist' using ($2 - ($2 % binwidth)):(1.0) with impulses

Instead we use the `timecolumn` function to get epoch seconds as a float. Most of the time we can rely on type coercion but to use the modulus (`%`) operator `t` needs to be converted to an int. Since `timecolumn` takes a format there's no need to set `timefmt` anymore. Also, we can avoid parsing the date twice and make the script more readable by defining a user-defined function we'll call `bin`.

`shellhist_gp_line.gnuplot`:

    set xdata time

    binwidth = 3600 # 1h in seconds
    bin(t) = (t - (int(t) % binwidth))

    plot 'shellhist' using (bin(timecolumn(2, "%Y-%m-%dT%H:%M:%S"))):(1.0) \
        smooth freq with linespoints

![`shellhist_gp_line.svg`](/post/histogram_gnuplot_vs_matplotlib/shellhist_gp_line.svg)

## Discontinuities

If we look closely at the chart above there's a discontinuity on June 28, from 1 to ~30. This is due to multiline commands in my shell history: lines after the first don't match the column specification given in the `using` clause and column 1 for these lines ends up being interpreted as `NaN`, resulting in a discontinuity in the data and multiple points being drawn for the same time interval. Instead of filtering the data with a separate script it was easier to ignore these lines using `set datafile missing NaN`. Sometimes discontinuities are easier to notice when plotted with the `boxes` plot style, where they show up as multiple lines within a box.

## Improve readability

If we wanted to share this chart there's a number of other worthwhile improvements:

- Add a title.
- Hide the legend ("key" in Gnuplot parlance), which is more distracting than useful in this case.
- Include time of day in the x-axis labels.
- Remove extraneous xtics, ytics, and border lines, depending on our preference.

Histograms are commonly plotted using boxes, which is particularly nice when the boxes cover the x-axis intervals they represent. By default boxes are centered on their x-value, so we need to change the `bin` function to offset them slightly. Also, we'll need to set `boxwidth`, since by default adjacent boxes are extended until they touch.

`shellhist_gp_bars.gnuplot`:

    binwidth = 3600 # 1h in seconds
    bin(t) = (t - (int(t) % binwidth) + binwidth/2)

    set xdata time
    set datafile missing NaN

    set boxwidth binwidth

    set xtics format "%b %d %H:%M" time rotate 
    set xtics nomirror
    set ytics nomirror
    set key off
    set border 1+2 # Set the bits for bottom and left borders.
    set title 'Commands Run Per Hour'

    plot 'shellhist' using (bin(timecolumn(2, "%Y-%m-%dT%H:%M:%S"))):(1.0) \
        smooth freq with boxes

![shellhist_gp_bars.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_gp_bars.svg)

## Multiple distributions with lines

Plotting multiple distributions with lines is only slightly trickier. For this data plotting all possible series would clutter the chart severely, so we instead find the most frequent commands using Gnuplot's `system` function and a pipeline and only plot those. Then we use the `plot` command's `for` clause to iterate over the data for each of the top commands, binning each separately by using ternary operator in the using clause to count one command per iteration.

If a line is missing columns then `stringcolumn(3)` will evaluate to `NaN` and a type error will be thrown when comparing it as a string to `cmd`. To avoid this we can clean up the file or use `valid` to check that a line has usable fields. `valid` only checks that columns aren't `NaN`, though, so we can't use it on string columns, as I was initially tempted to. `valid(3)` is always false since a string that don't contain numbers converts to `NaN` when coerced to a float.

While I don't want to plot all the series for the sake of readability, I would like to know how many command executions aren't covered by the top few, so I've also plotted a line showing the overal number of commands run per hour. As shown in the last line of the example the previous datafile given to a `plot` command can be reused by specifying the empty string (`''`), 

Most Gnuplot command names and modifiers can be abbreviated as long as they're unambiguous, and I've taken advantage of this by writing `u` instead of `using` for the first `plot` clause to help reduce the line length. Abbreviations are regularly used in examples I've seen on the web.

`shellhist_gp_stackedlines.gnuplot`:

    fmt = "%Y-%m-%dT%H:%M:%S"

    binwidth = 3600 # 1h in seconds
    bin(t) = (t - (int(t) % binwidth) + binwidth/2)

    set xdata time
    set datafile missing NaN

    set xtics format "%b %d %H:%M" time rotate
    set xtics nomirror
    set ytics nomirror
    set border 1+2 # Set the bits for bottom and left borders.
    set title 'Commands Run Per Hour'


    top_commands = system("awk '{print $3}' shellhist \
        | sort | uniq -c | sort -n | tail -n 5 | awk '{print $2}'")

    plot for [cmd in top_commands] 'shellhist' \
        u (bin(timecolumn(2, fmt))):((valid(1) && strcol(3) eq cmd) ? 1 : NaN) \
            smooth freq with linespoints title cmd, \
        '' using (bin(timecolumn(2, fmt))):(1.0) \
            smooth freq with linespoints title "sum"

![shellhist_gp_stackedlines.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_gp_stackedlines.svg)

## Multiple distributions with stacked bars

Plotting distributions using lines is convenient when making the chart, but if many distributions are involved the chart might be easier to read when plotted with stacked boxes/bars. While it's possible to create a stacked bar chart without reshaping the data it's awkward for more than a handful of series: the expressions get long and the plots must be precisely ordered so taller boxes don't completely obscure shorter ones. In the following script I'm using `@` macros[^macros] to shorten the plot command slightly, but it's still unweildly. Too error prone for my tastes. If Gnuplot's user-defined functions allowed some form of looping they could make this approach more feasible, but they can only contain a single expression and all Gnuplot looping constructs are parts of statements. 

`shellhist_gp_stackedbars.gnuplot`:

    binwidth = 3600 # 1h in seconds
    bin(t) = (t - (int(t) % binwidth) + binwidth/2)

    set xdata time
    set datafile missing NaN
    set boxwidth binwidth
    set xtics format "%b %d %H:%M" time rotate
    set style fill pattern 1

    time = '(bin(timecolumn(2, "%Y-%m-%dT%H:%M:%S")))'
    cmd = "stringcolumn(3)"

    plot 'shellhist' u @time:((valid(1) && (@cmd eq 'gnuplot' || @cmd eq 'fg')) ? 1 : NaN) \
            smooth freq w boxes t 'fg', \
        '' u @time:((valid(1) && @cmd eq 'gnuplot') ? 1.0 : NaN) \
            smooth freq w boxes t 'gnuplot'

![shellhist_gp_stackedbars.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_gp_stackedbars.svg)

So, if a stacked bar chart is needed, it seems better to bin the data and transpose the command names into columns of their own using a separate script, taking the data from this shape:

    time        cmd
    <timestamp> sed
    <timestamp> awk
    ...

To this:

    time  sed awk
    <bin>   0   5
    <bin>   5   2
    ...

I was almost able to reshape the data with [`mlr`](http://johnkerl.org/miller/doc/index.html) but ended up using perl. It's mostly a matter of counting frequencies per command for each bin, sorting the commands by frequency using a [Schwartzian transform](https://en.wikipedia.org/wiki/Schwartzian_transform) so it's easy to print the top N commands, and then printing out all the bins.

`bin.pl`:

    #!/usr/bin/perl

    use strict;
    use warnings FATAL => 'all';

    use Time::Piece;
    use List::Util qw(sum0 min max);

    my $bin_width = 3600;

    my %bins;
    my %cmd_seen;
    for my $line (<>) {
        my ($index, $time_str, $cmd) = split ' ', $line;
        next if $cmd !~ /^[a-zA-Z0-9_-]+$/;
        my $time = Time::Piece->strptime($time_str, "%Y-%m-%dT%H:%M:%S");
        my $interval = $time->epoch() - $time->epoch() % $bin_width;
        $bins{$interval}{$cmd}++;
        $cmd_seen{$cmd}++;
    }

    my %total_for;
    for my $bin (values %bins) {
        for my $cmd (keys %{$bin}) {
            $total_for{$cmd} += $bin->{$cmd};
        }
    }
    my @cmds = map {$_->[0]}
               sort {$b->[1] cmp $a->[1]} # hi to lo
               map {[$_, $total_for{$_}]}
               keys %total_for;

    my $ofs = ' ';
    print join($ofs, 'time', 'sum', @cmds), "\n";

    my ($start, $end) = (min(keys %bins), max(keys %bins));
    for (my $interval = $start; $interval <= $end; $interval += $bin_width) {
        my @row;
        push @row, gmtime($interval)->strftime("%Y-%m-%dT%H:%M:%S");
        push @row, sum0(values %{$bins{$interval}});
        for my $cmd (@cmds) {
            push @row, $bins{$interval}{$cmd} // 0;
        }
        print join($ofs, @row), "\n";
    }

Producing data like:

    $ perl bin.pl shellhist | tee shellhist_binned
    time sum gnuplot fg qiv man go less perl vim echo dicedist cat history find printf ls sort wc meh cd nl tac mv rm sed ll uniq pf wget mkdir help reset seq for
    2017-06-27T20:00:00 10 0 0 0 5 0 0 0 0 5 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    2017-06-27T21:00:00 11 0 0 0 1 0 0 3 2 1 0 4 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    2017-06-27T22:00:00 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    2017-06-27T23:00:00 2 0 0 0 0 1 0 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
    2017-06-28T00:00:00 10 7 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 2 0 0 0 0 0 0 0 0 0 1 0 0 0 0
    ...

Now the `histogram` plot type can be used with Gnuplot. `set style histogram rowstacked` asks for stacked bars instead of the default clustered bars, which don't work well with a large number of bins like we have here.

The x-axis labels require a different approach from before. Histograms in Gnuplot don't work with `set xdata time`, so the data needs to contain all the bins we want plotted, including empty ones. If the times in the datafile aren't in the presentation format desired, the x-axis tick labels can be formatted by giving an `xticlabels()` specification in the `using` clause and parsing and reformatting the dates using the `strptime` and `strftime` functions. Unfortunately, the usual methods of setting major and minor tick frequency, `set xtics <num>` and `set mxtics <num>`, don't work with `xticlabels`, but we can get a fair bit of control using an expression that returns either a string or `NaN` to choose which labels to show, like in the `xlabel` function below, which uses chained ternary operators to print a labelled tick every 6 hours and to fake minor ticks by making a tick with an empty label 3 hours between the labelled ones.

We're using the Tableau10 colour series as defined in [`matplotlib.cm.tab10`](http://matplotlib.org/examples/color/colormaps_reference.html) by selecting "words" out of a string in the `color` function. It seems difficult to find more than about 10 easily distinguishable colours, so I'm only plotting the top 10. I couldn't confidently identify series when using Tableau20.

The first plot clause prints the overall command frequency stored in the `sum` column and takes care of the xticlabels. Since the rest of the columns are command frequencies sorted in decreasing order we can easily plot the top N commands by changing the iteration conditions of the second clause.

`shellhist_gp_histogram.gnuplot`:

    # Autotitle series in the key using columnheaders from the data file.
    set key autotitle columnheader

    set style histogram rowstacked

    set xtics nomirror rotate
    set mxtics 11
    set style fill solid border -1

    color(i) = (word(tab10, i % words(tab10) + 1))
    tab10 = "#8c564b #e377c2 #7f7f7f #bcbd22 #17becf \
        #1f77b4 #ff7f0e #2ca02c #d62728 #9467bd"

    xlabel(time) = ( \
        t = strptime("%Y-%m-%dT%H:%M:%S", time), \
        int(tm_hour(t)) % 12 == 0  ? strftime("%b %d %H00", t) \
        : int(tm_hour(t)) % 3 == 0 ? "" \
        :                            NaN \
    )

    topN = 10
    plot 'shellhist_binned' u "sum":xtic(xlabel(strcol(1))) w lines, \
        for [i=3:(3+topN-1)] '' using i with histogram linecolor rgb color(i)

![shellhist_gp_histogram.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_gp_histogram.svg)

# matplotlib

## Dates, times, and timezones

matplotlib includes some convenient date-handling code, particularly for locating and formatting axis ticks, but if we want to take advantage of this we need to give matplotlib our dates in its own format, a float representing the number of days since 0001-01-01 in UTC. Because the format is in UTC and timezone-naïve [`datetime.datetime`](https://docs.python.org/3.7/library/datetime.html#datetime-objects) assume the local timezone, any `datetime.datetime` objects converted using `matplotlib.dates.date2num` must be either timezone-aware or in UTC themselves.

The standard `datetime` module provides the [`tzinfo`](https://docs.python.org/3.7/library/datetime.html#datetime.tzinfo`) interface to add timezone information to `datetime.datetime` instances, but only provides a concrete implementation for simple timezone offsets that don't take DST or other changes into account. Also, `datetime.datetime.strptime` can only parse timezone offsets formatted as `[-+]HHMM`. For other cases additional libraries will likely be needed. In particluar, if timezone abbreviations are being parsed other libraries like `dateutil`, a dependency of matplotlib, can be used to help disambiguate them, seeing as there are [many collisions](https://www.timeanddate.com/time/zones/).

Also, unless we want to display UTC times in our charts we need to give a timezone to matplotlib to use for formatting. We can change matplotlib's runtime configuration setting by giving an [Olson](https://en.wikipedia.org/wiki/Zoneinfo) timezone name in our [`matplotlibrc`](http://matplotlib.org/users/customizing.html) file, or we can override the rc value in code by using `matplotlib.rcParams` or by passing an object that implements the [`datetime.tzinfo`](https://docs.python.org/3.6/library/datetime.html#tzinfo-objects) interface to all our [`Locator`](http://matplotlib.org/api/ticker_api.html#matplotlib.ticker.Locator) and [`Formatter`](http://matplotlib.org/api/ticker_api.html#matplotlib.ticker.Formatter) objects.[^tzlocal]  I'd rather not override anyone's settings, so I've just set `timezone: America/Edmonton` in my `~/.config/matplotlib/matplotlibrc`.

## Points

Let's start with the same type of chart as with Gnuplot, a point for each command executed, randomly-scattered from [0,1] across the y-axis. This gives a rough idea of when commands were executed. Getting the data out of the `shellhist` file is straight-forward but verbose compared to Gnuplot, and numpy is convenient for generating a large array of random y-values. Note I've been careful to convert the `datetime.datetime` objects resulting from parsing times to Unix time in UTC before converting them to matplotlib's time representation.[^diyfmt] 

`shellhist_mpl_points.py`:

    from datetime import datetime
    import matplotlib.pyplot as plt
    from matplotlib.dates import epoch2num
    import numpy as np

    times = []
    for line in open('shellhist'):
        fields  = line.split()
        if len(fields) < 3:
            continue
        _, time_str, cmd = fields[:3]
        unixtime = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S").timestamp()
        times.append(epoch2num(unixtime))

    fig, ax = plt.subplots()
    fig.autofmt_xdate() # Rotate and right-align xtic labels.

    ax.plot_date(times, np.random.rand(len(times)), '+')

    plt.savefig('shellhist_mpl_points.svg')

![shellhist_mpl_points.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_mpl_points.svg)


## Binning times

matplotlib doesn't have anything like Gnuplot's `smooth frequency` filter (AFAIK), making it less convenient to do a quick-and-dirty line chart. It seems necessary to preprocess the data before plotting it. I looked at using numpy's `histogram` function or `matplotlib.axes.Axes.hist` but it seems easier to count the frequency per bin using a `defaultdict`.

For bin widths that evenly divide a day, timestamps are most easily binned when represented as Unix time since every day is defined to have exactly 86400 seconds [according to POSIX](http://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_16) regardless of leap seconds and it's easy to use the modulus operator, `%`, on an integer to find the start of some number of seconds, minutes, or hours. Wheras rounding `datetime.datetime` instances seems to require cascading through the different units, and rounding matplotlib's days-since-0001-01-01 representation involves dealing with floats, which are tricky to compare or round reliably and thus a bad choice for dictionary keys.

`shellhist_mpl_binned_overall.py`:

    from collections import defaultdict
    from datetime import datetime, timedelta
    import matplotlib.pyplot as plt
    from matplotlib.dates import epoch2num

    bin_width = timedelta(hours=1)

    freq_for = defaultdict(lambda: 0)
    for line in open('shellhist'):
        fields  = line.split()
        if len(fields) < 3:
            continue
        _, time_str, cmd = fields[:3]
        unixtime = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S").timestamp()
        bin_start = unixtime - unixtime % bin_width.seconds
        freq_for[bin_start] += 1


    unixtimes = list(sorted(freq_for.keys()))
    times = [epoch2num(t) for t in unixtimes]
    freqs = [freq_for[bin] for bin in unixtimes]
    
    fig, ax = plt.subplots()
    fig.autofmt_xdate()

    ax.plot_date(times, freqs, linestyle='-')

    plt.savefig('shellhist_mpl_overall_line.svg')

![shellhist_mpl_overall_line.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_mpl_overall_line.svg)

## Improve readability

Assuming we liked how the Gnuplot single-distribution line chart was styled, we can create a similar chart in matplotlib.

First, use `DateFormatter` and `HourLocator` objects instead of `Figure.autofmt_xdate` to choose xtick placement and labels:

- format the xtick labels as "Jan DD HHHH" and only label midnight and noon
- add minor xticks every 3 hours

We also:

- hide the top and right "spines", as matplotlib calls the `Axes` borders
- rotate the xticklabels to vertical. It's harder to read the label itself but clearer which point on the axis the label refers to.
- add a title

`shellhist_mpl_binned_overall_nicer.py`:

    from collections import defaultdict
    from datetime import datetime, timedelta
    import matplotlib.pyplot as plt
    from matplotlib.dates import epoch2num, DateFormatter, HourLocator

    bin_width = timedelta(hours=1)

    freq_for = defaultdict(lambda: 0)
    for line in open('shellhist'):
        fields  = line.split()
        if len(fields) < 3:
            continue
        _, time_str, cmd = fields[:3]
        unixtime = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S").timestamp()
        bin_start = unixtime - unixtime % bin_width.seconds
        freq_for[bin_start] += 1


    unixtimes = list(sorted(freq_for.keys()))
    times = [epoch2num(t) for t in unixtimes]
    freqs = [freq_for[bin] for bin in unixtimes]
    
    fig, ax = plt.subplots()

    plt.xticks(rotation='vertical')
    ax.spines['right'].set_visible(False)
    ax.spines['top'].set_visible(False)
    ax.xaxis.set_major_formatter(DateFormatter("%b %d %H00"))
    ax.xaxis.set_major_locator(HourLocator(byhour=range(0, 24, 12)))
    ax.xaxis.set_minor_locator(HourLocator(byhour=range(0, 24, 3)))
    ax.set_title("Commands Run Per Hour")

    ax.plot_date(times, freqs, linestyle='-')

    plt.savefig('shellhist_mpl_overall_line_nicer.svg')

![shellhist_mpl_overall_line_nicer.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_mpl_overall_line_nicer.svg)

## Multiple distributions

In matplotlib we can work from the same binned data whether we're plotting lines or bars so I'm generating both from the same script here. The script is pretty long so I've organized it into functions.

Binning is mostly the same as before, except we're filtering out commands that don't look like words using a regular expression and using nested `defaultdict`s to also keep track of per-command frequency.

The styling code in `save_chart` is almost the same as before, except `Axes.legend` is called between plotting all the series and saving the figure, since it generates a legend based on the series that have already been plotted.

I've set the line/bar colors to be `tab10` using `Axes.set_prop_cycle` in `save_chart` just to show one way to change to them. [This example](http://matplotlib.org/examples/color/color_cycle_demo.html) show some other ways. `tab10` is the default colour cycle, so it's not actually doing anything.

Plotting lines is straightforward, but plotting stacked bars requires a few extra steps. As with Gnuplot we've offset the times by half a `bin_width` and set the bar width so the bars cover the time interval on the x-axis they represent instead of being centered over it.  Also, we need to keep track of the where to plot the bottom of the bars and add the frequencies of each series to it; a numpy array is convenient and efficient for this since operations on an array apply to all of its elements.

`shellhist_mpl_multi.py`:

    from collections import defaultdict, namedtuple
    from cycler import cycler
    from datetime import datetime, timedelta
    from matplotlib.dates import epoch2num, DateFormatter, HourLocator
    import matplotlib.pyplot as plt
    import numpy as np
    import re

    # cmds: list of command names in decreasing order
    # unix_times: bin start times
    # freqs_for: dict of command names to numpy arrays of bin frequencies
    # totals: numpy array of overall command frequencies for each bin
    # bin_width: bin width as datetime.timedelta
    CmdFreq = namedtuple('CmdFreq',
        ['cmds', 'unix_times', 'freqs_for', 'totals', 'bin_width'])

    plt.rcParams['image.cmap'] = 'tab10'

    def save_chart(plot_func, data, filename):
        fig, ax = plt.subplots()

        plt.xticks(rotation='vertical')
        ax.spines['right'].set_visible(False)
        ax.spines['top'].set_visible(False)
        ax.xaxis.set_major_formatter(DateFormatter("%b %d %H00"))
        ax.xaxis.set_major_locator(HourLocator(byhour=range(0, 24, 12)))
        ax.xaxis.set_minor_locator(HourLocator(byhour=range(0, 24, 3)))
        ax.set_prop_cycle(cycler('color', plt.get_cmap('tab10').colors))
        ax.set_title("Commands Run Per Hour")

        plot_func(ax, data)

        ax.legend() # Called after all data has been plotted.

        plt.savefig(filename)

    def plot_bars(axes, data):
        bar_offset = data.bin_width.seconds/2
        offset_times = [epoch2num(t + bar_offset) for t in data.unix_times]
        bar_width = data.bin_width.seconds / 86400.0 # Fraction of a day.

        axes.plot(offset_times, data.totals,
            linestyle='-', linewidth=0.2, label='sum')

        bottom = np.zeros(len(offset_times))
        for cmd in data.cmds[:10]:
            axes.bar(offset_times, data.freqs_for[cmd],
                bottom=bottom, width=bar_width, label=cmd)
            bottom += data.freqs_for[cmd]

    def plot_lines(axes, data):
        float_times = [epoch2num(t) for t in data.unix_times]
        axes.plot(float_times, data.totals, linewidth=0.2, label='sum')

        for cmd in data.cmds[:10]:
            axes.plot(float_times, data.freqs_for[cmd], label=cmd)


    def get_cmd_data(bin_width):
        with open('shellhist') as shellhist:
            bin_for, bin_total_for = bin_cmds(shellhist, bin_width)

        cmds = cmds_in_decreasing_freq(bin_for)

        unix_times = np.array(sorted(bin_for.keys()), int)

        freqs_for = {}
        for cmd in cmds:
            freqs_for[cmd] = np.array([bin_for[t][cmd] for t in unix_times])

        totals = np.array([bin_total_for[t] for t in unix_times])

        return CmdFreq(cmds, unix_times, freqs_for, totals, bin_width)

    def bin_cmds(event_lines, bin_width):
        bin_for = defaultdict(lambda: defaultdict(lambda: 0))
        bin_total_for = defaultdict(lambda: 0)
        for line in event_lines:
            fields  = line.split()
            if len(fields) < 3:
                continue
            _, time_str, cmd = fields[:3]

            if not re.search(r'^[a-zA-Z0-9_-]+$', cmd):
                continue

            date = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S")
            unixtime = int(date.timestamp())
            bin_start = unixtime - unixtime % bin_width.seconds

            bin_for[bin_start][cmd] += 1
            bin_total_for[bin_start] += 1

        return bin_for, bin_total_for

    def cmds_in_decreasing_freq(bin_for):
        freq_for = defaultdict(lambda: 0)
        for bin_ in bin_for.values():
            for cmd, freq in bin_.items():
                freq_for[cmd] += freq
        pairs = sorted(freq_for.items(), key=lambda pair: pair[1])
        return list(reversed([p[0] for p in pairs]))

    if __name__ == '__main__':
        data = get_cmd_data(timedelta(hours=1))
        save_chart(plot_bars, data, 'shellhist_mpl_stacked_bars.svg')
        save_chart(plot_lines, data, 'shellhist_mpl_stacked_lines.svg')

![shellhist_mpl_stacked_bars.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_mpl_stacked_bars.svg)
![shellhist_mpl_stacked_lines.svg](/post/histogram_gnuplot_vs_matplotlib/shellhist_mpl_stacked_lines.svg)

# Best resources for learning

To learn more about Gnuplot I'd recommend reading [the manual](http://gnuplot.info/docs_5.0/gnuplot.pdf), skimming less relevant sections but paying particular attention to most of part 1 and the description of the `plot` command in part 3. Once these fundamental topics are understood I think the rest can be looked up as needed. At first glance the manual doesn't look like it's organized for a linear read but I was well-served by that approach. Looking through the collection of [demos](http://gnuplot.sourceforge.net/demo_5.0/) may also be helpful.

I learned what I know about matplotlib by stumbling through the official docs, which was painful and inefficient. They're clearly written and comprehensive but it was difficult to find what I needed to do practical things. I suspect having such comprehensive API docs creates a [Worse is Better](https://www.jwz.org/doc/worse-is-better.html) situation making the creation of tutorial-style documentation seem like a relatively low-value activity since all the needed information is already out there somewhere and duplicating it in a tutorial increases the maintenance burden. I'd recommend starting with [Nicolas Rougier's tutorial](http://www.labri.fr/perso/nrougier/teaching/matplotlib/) over the ones on [matplotlib.org](http://matplotlib.org/users/tutorials.html).

# Conclusion

I'm impressed with both tools; they both render beautiful charts. As I mentioned in the intro I'd lean towards Gnuplot for simpler, quicker tasks since it so convenient and concise, and towards matplotlib for fancier stuff, since it seems like everything imaginable is customizable if you pound your head against the docs for a bit. When each chart is defined in a separate script Gnuplot is kicky fast compared to matplotlib, I think largely due to the time it takes to import all the matplotlib libraries; it probably doesn't matter but it still bolsters my warm feelings of convenience for Gnuplot.


[^using]: A description of the `using` clause of the plot command can be found in the "Commands > Plot > Data > Using" section of [Gnuplot's manual](http://gnuplot.info/docs_5.0/gnuplot.pdf). The manual is an excellent reference but isn't obviously a tutorial, and before reading most of it I had trouble finding the information I needed. I wish it was in HTML so I could link directly to relevant sections, but it's only published in PDF so the best I can do is provide section breadcrumbs.
[^smooth]: The "Commands > Plot > Data > Smooth > Frequency" section of the Gnuplot manual has an example of plotting a histogram with the `lines` plotting style.
[^leap]: Note that one limitation of rounding the epoch seconds time representation like this is that leap seconds aren't taken into account. If leap second accuracy is required for your application a different approach is needed.
[^time_repr]: See the "Gnuplot > Time/Date Data" section of the manual.
[^macros]: See the "Gnuplot > Substitution and Command line macros" section of the manual.
[^timezone]: See the default value of the `timezone` setting in the [sample `matplotlibrc`](http://matplotlib.org/users/customizing.html#matplotlibrc-sample) and the discussion of timezones in the [`matplotlib.dates` docs](http://matplotlib.org/api/dates_api.html#module-matplotlib.dates).
[^tzlocal]: `dateutil.tz.tzlocal` returns a `datetime.tzinfo`-conforming object for the local time zone.
[^diyfmt]: Alternatively, it's straightforward to stick with Unix times and use `matplotlib.dates.FuncFormatter` and `MultipleLocator` instead, but I'm trying to go with the grain of matplotlib.
