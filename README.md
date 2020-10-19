# Play multiple playlists within multiple zones

[![Import](https://cdn.infobeamer.com/s/img/import.png)](https://info-beamer.com/use?url=https://github.com/info-beamer/package-zone-player)

This is a small example package showing how to build a simple player
that displays multiple independant playlists within configurable
zones. The content can be rotated as well.

You should *not* attempt to play multiple FullHD videos. Doing so might
be too much for the Pi and it might cause a lost video signal as the
Pi cannot generate and HDMI output signal fast enough. It's best to
use videos/images that exactly fit into the available zone space, so the
Pi doesn't have to rescale the output. So if you create a 1080x1080 zone,
try to use 1080x1080 videos.
