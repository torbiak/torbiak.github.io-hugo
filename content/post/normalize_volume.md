+++
title = "Normalize volume system-wide with PulseAudio"
date = "2023-12-20"
tags = ["linux", "pulseaudio", "systemd", "audio", "udev", "bluetooth"]
description = "How to use a LADSPA compressor filter to normalize volume system-wide, and to use udev rules, a systemd user service, and PulseAudio commands to make the necessary config changes when connecting/disconnecting Bluetooth headphones."
toc = true
+++

# Motivation

I usually watch YouTube videos while I wash dishes, and if videos have very different volume levels it can be either annoying to not understand what's being said or painful to endure loud sounds while I dry my hands so that I can adjust the volume. So I've been delighted over the past couple years using a compressor filter from [Steve Harris' LADSPA plugin suite](http://plugin.org.uk/) with PulseAudio to normalize volume for all audio output from my laptop. I'm quite willing to trade dynamic range for listening comfort, and for me even music doesn't sound noticeably worse with the compressor filter.

In case you're wondering, [LADSPA](http://ladspa.org/) is the Linux Audio Developer's Simple Plugin API, and basically it's an interface for shared libraries that allows plugins to define some control ports/params and give callbacks to process samples. It's like a simpler version of [VST](https://en.wikipedia.org/wiki/Virtual_Studio_Technology), if you've ever used synth or effects plugins in a DAW and have heard of that.

# PulseAudio configuration

For configuring PulseAudio I referred to [this answer on the Ask Ubuntu StackExchange](https://askubuntu.com/a/44012). On Arch I installed the `swh-plugins` package. I then added a PulseAudio config drop-in under `/etc/pulse/defaultpa.d`, although you could instead add it to a per-user config in `$XDG_CONFIG_HOME/pulse/client.conf`, [as described on the Arch wiki](https://wiki.archlinux.org/title/PulseAudio/Examples#Creating_user_configuration_files). For PulseAudio CLI syntax and commands, see the `pulse-cli-syntax(5)` manpage.

Sorry about the long lines in this and several other snippets, but neither PulseAudio CLI syntax or udev rules support line continuations and the likely confusion over including "fake" ones doesn't seem worth it.

`/etc/pulse/defaultpa.d/compressor.pa`:

    .ifexists module-ladspa-sink.so
    .nofail
    load-module module-ladspa-sink sink_name=compressor plugin=sc4_1882 label=sc4 control=1,1.5,401,-30,20,5,24
    set-default-sink compressor
    .fail
    .endif

`module-ladspa-sink` takes a `sink_master` param (previously named `master`) to define where the processed audio goes, but I'm leaving it as the default. See [the PulseAudio builtin module docs](https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/Modules/#module-ladspa-sink). If you wanted to route the output to a different sink, you can find its name with `pactl list short sinks`.

I'm still using the SC4 filter settings from that Ask Ubuntu answer, except that I've increased the makeup gain so there's a smaller volume difference between having the filter on/off, to avoid having sound blaring if I ever accidentally turn off the filter. Mostly the knobs are cranked to always be compressing as soon and hard as possible, except knee radius, which is set in the middle of the allowed values, but when adjusting it I can't notice a difference. With these settings it feels like the volume is always being reduced, which seems good to me.

- RMS/peak ratio: 1
- Attack time (ms): 1.5
- Release time (ms): 401
- Threshold level (dB): -30
- Gain reduction ratio (1:n): 20
- Knee radius: 5
- Makeup gain (dB): 24

If you want to get a better sense of how the filter params work and see their allowed ranges, here's [the code for the SC4 filter](https://github.com/swh/ladspa/blob/master/sc4_1882.xml). And if you're looking at the code you might also want to peek at [the little LADSPA spec](http://ladspa.org/ladspa_sdk/ladspa.h.txt).

After writing the PulseAudio config, I use `pulseaudio -k` to kill the server, and then the stock `systemd` config for my system immediately restarts it for me with the new settings. I can see any errors with my PulseAudio config by following syslog with `journalctl -f`.

The above config might be all you need, but I needed to do a bit more to have things work with my Bluetooth headphones.

# Manually route a LADSPA sink to Bluetooth headphones

When you connect Bluetooth headphones a new sink gets added to PulseAudio, but unless we do something our compressor is going to stay routed to our ALSA output or wherever we pointed it at PulseAudio startup, and the output to the headphones won't be filtered. For a few years I was keeping a `pavucontrol` window open and manually rerouting the compressor's output to my headphones after connecting them, but when I set up my new laptop `pavucontrol` no longer gave me a dropdown to do manual routing for LADSPA sinks, and I haven't figured out why yet. So, I started running a little script every time I connected my headphones, which adds another LADSPA sink with the output routed to my headphones. The sink name is based on the headphones' MAC address, and is constant, so I just needed to look it up once using `pactl list short sinks` and provide it as the `sink_master` param.

    pacmd <<EOF
    load-module module-ladspa-sink sink_name=bluetooth_compressor plugin=sc4_1882 label=sc4 sink_master=bluez_sink.00_1B_66_A1_45_12.a2dp_sink control=1,1.5,401,-30,20,5,24
    set-default-sink bluetooth_compressor
    EOF

After disconnecting the headphones the LADSPA sink gets destroyed, so back when I was doing the routing in `pavucontrol` I would either need to change the LADSPA sink's master back to my soundcard before disconnecting my headphones to avoid it getting destroyed, or I'd need to recreate the sink by restarting pulseaudio. With my new laptop my problem was that after the LADSPA sink for my headphones was destroyed, PulseAudio would choose my soundcard as the default sink instead of the compressor that outputs to it. I could run another script after disconnecting my headphones, but instead I finally had the motivation to automate the routing. I couldn't figure out how to fix this with the [builtin PulseAudio modules](https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/Modules/), and I considered writing a PulseAudio module to allow prioritizing sinks, but running shell scripts on Bluetooth connection/disconnection events seemed easier and more flexible.

# Automatically route a LADSPA sink to Bluetooth headphones

## Find udev info

udev is part of systemd and lets us run shell scripts or start systemd services on hardware events. `udev(7)` is a useful reference when writing rules, and [the Arch wiki page on it](https://wiki.archlinux.org/title/Udev) has some good info, too. Before writing the rule I needed to find some way to identify my headphones. By running `udevadm monitor` before connecting my headphones, I could see the related devices the kernel makes on connection:

    $ udevadm monitor
    ...
    KERNEL[80470.275026] add      /devices/pci0000:00/0000:00:08.1/0000:c1:00.3/usb1/1-5/1-5:1.0/bluetooth/hci0/hci0:50 (bluetooth)
    UDEV  [80470.276714] add      /devices/pci0000:00/0000:00:08.1/0000:c1:00.3/usb1/1-5/1-5:1.0/bluetooth/hci0/hci0:50 (bluetooth)
    KERNEL[80472.139125] add      /devices/virtual/input/input28 (input)
    KERNEL[80472.139222] add      /devices/virtual/input/input28/event13 (input)
    UDEV  [80472.140796] add      /devices/virtual/input/input28 (input)
    UDEV  [80472.172162] add      /devices/virtual/input/input28/event13 (input)

And I could get more information about devices with `udevadm info -ap`:

    $ udevadm info -ap /devices/virtual/input/input28
    ...
      looking at device '/devices/virtual/input/input28':
        KERNEL=="input28"
        SUBSYSTEM=="input"
        DRIVER==""
        ...
        ATTR{id/bustype}=="0005"
        ATTR{id/product}=="004b"
        ATTR{id/vendor}=="0082"
        ATTR{id/version}=="0103"
        ATTR{inhibited}=="0"
        ATTR{name}=="HD1 M2 AEBT (AVRCP)"
        ATTR{phys}=="14:ac:60:46:87:9e"
        ...

I don't know how to write a udev rule that would match all Bluetooth headphones, but this is enough information to write a rule for my specific ones, at least. An important thing to note now, though, is that the pulseaudio daemon is per-user, so I need to run `pacmd` as my user. I could use the `RUN` operator in the udev rule along with `sudo -u <user>` and have separate rules for `ACTION=="add"` and `ACTION=="remove"`, but hard-coding my username feels kinda bad, so instead I went with using `ENV{SYSTEMD_USER_WANTS}` and writing a device-bound systemd user service that'll automatically be stopped when the device goes away. To make that work, I need to `TAG+="systemd"` the device so systemd picks it up, and somehow give the device name that systemd uses to a parametrized service ("instantiated" in systemd parlance), so it can be bound to it.

With a udev rule like this in `/etc/udev/rules.d/99-sennheiser.rules`:

    ACTION=="add", ATTR{name}=="HD1 M2 AEBT (AVRCP)", TAG+="systemd"

And after reloading the udev rules:

    sudo udevadm control --reload

When I connect the headphones I see a corresponding device in my `systemctl` output:

    UNIT                                      LOAD    ACTIVE  SUB      DESCRIPTION
    sys-devices-virtual-input-input28.device  loaded  active  plugged  /sys/devices/virtual/input/input28

Which is cool, but not terribly useful yet. We'll come back to writing the udev rule. First I need to figure out what the systemd user service will be like, so I know what parameters it needs.

## systemd user service

Instantiated systemd services are named such that there's an `@` before the unit extension and then, when being started, they can be given an argument in their name after the `@`. For example, if you run `systemctl` you'll probably see a `getty@tty1.service`, where `getty@.service` is the unit name and `tty1` is the argument. I put my service file at `$XDG_CONFIG_HOME/systemd/user/bt-compress@.service`. After modifying that file I need to run `systemctl --user daemon-reload` to load the changes and use `journalctl` when connecting my headphones to look for errors in syslog. There's not much point "installing" our service in the systemd sense, since we can't start it unless the headphones are connected, so our service file doesn't have an `[Install]` section, and it won't show up in `systemctl --user` output unless it's running or failed.

`$XDG_CONFIG_HOME/systemd/user/bt-compress@.service`:

    [Unit]
    BindTo=%i.device
    After=%i.device

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    ExecStart=%h/bin/bt-compress start
    ExecStop=%h/bin/bt-compress stop

By default a systemd service is `Type=simple` and the `ExecStart` option will run a long-running process, but we just need to run some short shell scripts at the beginning and end of the device's life. Looking through `systemd.service(5)`, we see that for `Type=oneshot` the service is considered up after the `ExecStart` program exits for the purpose of starting dependencies, but it will soon transition to the "dead" state unless we also give `RemainAfterExit=yes`. We need it to "remain after exit" so that systemd has an active service to stop when the device goes away.

The escapes available in systemd units can be found in `systemd.unit(5)`. `%h` expands to the user's home directory and `%i` expands to the string between `@` and `.service` in the service name. So, we'd like to pass the extension-less systemd device unit name in there, which we saw in the last section was `sys-devices-virtual-input-input28`. But if I reconnect my headphones I see that the number at the end of the name increments each time I connect, so it seems like we'll need to get the device path and convert it to the systemd device unit name in the udev rule somehow.

## PulseAudio configuration script

But before we get to the udev rule, here's the script that our systemd service calls. It's pretty straightforward:

`~/bin/bt-compress`:

    #!/bin/bash
    set -euo pipefail

    log() {
        local lvl=${1:?No level given}; shift
        local msg=${1:?No message given}; shift
        logger -p "$lvl" -t bt-compress "$msg"
    }

    usage="bt-compress start|stop"
    if [[ $# -ne 1 ]]; then
        echo "$usage" >&2
        exit 1
    fi
    cmd=${1}; shift
    case "$cmd" in
    start)
        log info 'set bluetooth_compressor as default sink'
        pacmd <<EOF
    load-module module-ladspa-sink sink_name=bluetooth_compressor plugin=sc4_1882 label=sc4 sink_master=bluez_sink.00_1B_66_A1_45_12.a2dp_sink control=1,1.5,401,-30,20,5,12
    set-default-sink bluetooth_compressor
    EOF
    ;;
    stop)
        log info 'set compressor as default sink'
        pacmd 'set-default-sink compressor'
    ;;
    *)
        echo "unexpected cmd: $cmd" >&2
        exit 1
    ;;
    esac

## udev rule

Finally, let's wire up udev and systemd. According to `systemd.device(5)`, the `SYSTEMD_USER_WANTS` udev device property adds a `Wants=` dependency from a device to a service, and is read by user service manager instances. And according to `udev(7)`, we can set device properties using `ENV{<key>}=<value>`. And if we use `udevadm test` to inspect the device properties, we can see that the `DEVPATH` property is included:

    $ sudo udevadm test --action="add" /devices/virtual/input/input28
    ...
    DEVPATH=/devices/virtual/input/input28
    PRODUCT=5/82/4b/103
    NAME="HD1 M2 AEBT (AVRCP)"
    PHYS="14:ac:60:46:87:9e"
    PROP=0
    EV=100007
    KEY=...
    REL=0
    MODALIAS=...
    ACTION=add
    SUBSYSTEM=input
    TAGS=:seat:systemd:
    ID_INPUT=1
    ID_INPUT_KEY=1
    ID_BUS=bluetooth
    CURRENT_TAGS=:seat:systemd:
    SYSTEMD_USER_WANTS=bt-compress@.service
    USEC_INITIALIZED=259580475046

Apparently we're doing what systemd considers the usual thing, since if we just set `SYSTEMD_USER_WANTS` to our base service name, `bt-compress@.service`, it'll automatically pick up the `DEVPATH` from the udev event, prefix it with the sysfs mount point, escape it, and give the escaped device path as the argument to our service. So our udev rule can just be this:

    ACTION=="add", ATTR{name}=="HD1 M2 AEBT (AVRCP)", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="bt-compress@.service"

If you have trouble getting this to work, using `udevadm test` as above can be useful, as it prints a bunch of diagnostics, which I have elided here.

But if we needed to do the escaping ourselves, we could use `systemd-escape`:

    $ systemd-escape --template bt-compress@.service --path /sys/devices/virtual/input/input28
    bt-compress@sys-devices-virtual-input-input28.service

And surprisingly to me, there's a udev key for running shell commands and capturing their output: the `PROGRAM` key. The results of `PROGRAM` are then available via the `%c` or `$result` escape, and while the manpage doesn't currently include the `ENV` key in the list of keys where escapes are available, it apparently works. Note that `$devpath` doesn't include the sysfs mount point, so we need to add it when running `systemd-escape`.

    ACTION=="add", ATTR{name}=="HD1 M2 AEBT (AVRCP)", TAG+="systemd", PROGRAM="/usr/bin/systemd-escape -p --template=bt-compress@.service /sys$devpath", ENV{SYSTEMD_USER_WANTS}+="$result"

# Good luck

I doubt you got this far unless you're motivated enough to set something similar up on your own machine. Good luck, and I hope this helped.
