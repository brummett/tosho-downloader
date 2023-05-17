#!/usr/local/bin/raku

use Task::KrakenDownloader;
use Task::GofileDownloader;

my %dl-classes = kraken => Task::KrakenDownloader,
                 gofile => Task::GofileDownloader;
sub MAIN(
    Str $downloader,
    Str $url
) {

    my $filename = 'dlfile';

    unless %dl-classes{$downloader.lc()}:exists {
        say "downloader: " ~ $downloader.lc;
        die "Unrecognized downloader, expected: " ~ %dl-classes.keys.join(', ');
    }

    my $dl = %dl-classes{$downloader.lc}.new(filename => $filename, url => $url);
    $dl.run();
    say "Downloaded to file 'dlfile'";
    rename $dl.pathname, $filename, :createonly;
}
