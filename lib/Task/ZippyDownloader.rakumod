use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri;
use DOM::Tiny;

unit class Task::ZippyDownloader does FileDownloader is Task;

method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    my $dom = DOM::Tiny.parse(await $response.body);

    my $original-uri = $response.request.uri;

    my @parsers = &parser1;

    for @parsers -> $parser {
        if my $download-path = $parser($dom) {
            say "Download link in $original-uri is $download-path";
            my $dl-uri = $original-uri.add($download-path);
            return $dl-uri;
        }
    }
    die "Didn't find download link on $original-uri"
}

sub parser1($dom) {
    # ZippyShare has a little bit of javascript that calculates the right
    # URL for the "DOWNLOAD NOW" link or obfuscate it.  It's in a <script>
    # block right after the download link.
    my $script = $dom.find('a#dlbutton + script')[0];

    # The script does a thing like this:
    #   document.getElementById('dlbutton').href = "/d/RjdUFwva/" + (518720 % 51245 + 518720 % 913) + "blahblah"
    if $script and $script ~~ /'document.getElementById(\'dlbutton\').href = "' $<baseURL>=<-["]>+
                    '" + ('
                    $<d1>=\d+
                    ' % '
                    $<d2>=\d+
                    ' + '
                    $<d3>=\d+
                    ' % '
                    $<d4>=\d+
                    ') + "'
                    $<remainURL>=<-["]>+ '"'/
    {
        my $download-path = ~$<baseURL>
                            ~ ( (~$<d1>.Int % ~$<d2>.Int) + (~$<d3>.Int % ~$<d4>.Int ) )
                            ~ ~$<remainURL>;
        return $download-path;
    }
    return;
}
