# Note that ZippyShare is shut down and Tosho no longer uses them

use FileDownloader;
use Task;

use Cro::HTTP::Response;
use Cro::Uri;
use DOM::Tiny;

unit class Task::ZippyDownloader does FileDownloader is Task;

method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) {
    my $dom = DOM::Tiny.parse(await $response.body);

    my $original-uri = $response.request.uri;

    my @parsers = &parser2, &parser1;

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

sub parser2($dom) {
    # There are multiple <script> blocks.  One defines a function named "somffunction".
    # It does a thing like this:
    #   document.getElementById('dlbutton').omg = 782518%78956;
    #   var b = parseInt(document.getElementById('dlbutton').omg) * (782518%3);
    #   var e = function() {if (false) {return a+b+c} else {return (a+3)%b + 3}};  // irrevelant line
    #   document.getElementById('dlbutton').href    = "/d/dLS9rSN9/"+(b+18)+"blahblah"
    #
    # The calculation for that thing in the middle becomes:
    #   (( d1 % $d2 ) * ( d3 % d4 )) + d5

    for $dom.find('script') -> $script {
        if $script ~~ /'var somffunction = function()'/
            and $script ~~ rx{'document.getElementById(\'dlbutton\').omg = '
                                $<d1>=\d+
                                '%'
                                $<d2>=\d+
                                ';' \s+ 'var b = parseInt(document.getElementById(\'dlbutton\').omg) * ('
                                $<d3>=\d+
                                '%'
                                $<d4>=\d+
                                ')' .*? 'document.getElementById(\'dlbutton\').href' \s+ '= "'
                                $<baseURL>=<-["]>+
                                '"+(b+' $<d5>=\d+ ')+"'
                                $<remainURL>=<-["]>+ '"' }
        {
            my $download-path = ~$<baseURL>
                                ~ (( ~$<d1>.Int % ~$<d2>.Int ) * ( ~$<d3>.Int % ~$<d4>.Int)) + ~$<d5>.Int
                                ~ ~$<remainURL>;
            return $download-path;
        }
    }
    return;
}
