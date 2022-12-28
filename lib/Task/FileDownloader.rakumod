use Cro::HTTP::Client;
use Cro::Uri;
use DOM::Tiny;

use Task; 

class Task::FileDownloader is Task {
    has Str $.filename;
    has Str $.url;

    method run { ... }

    method init {
        mkdir self.pathname;
    }

    method pathname { 'working/' ~ $.filename }
}

class Task::FileDownloader::ZippyShare is Task::FileDownloader {
    method run {
        say "Trying to download file from $.url";
        react {
            my $client = Cro::HTTP::Client.new();
            my $url = Cro::Uri.parse($.url);
            whenever $client.get($url) -> $response {
                if $response.content-type.type-and-subtype eq 'text/html' {
                    my $relative-download-path = self.get-download-link($response, $url);
                    say "Download link in $.url is $relative-download-path";
                    my $dl-uri = $url.add($relative-download-path);
                    self.do-download-file($client, $dl-uri);
                }
                QUIT {
                    default {
                        note "$url failed: " ~ .message;
                    }
                }
            }
        }
        say "Download from $.url is done";
        self.done;
    }

    method get-download-link($response, $url) {
        my $dom = DOM::Tiny.parse(await $response.body);

        # ZippyShare has a little bit of javascript that calculates the right
        # URL for the "DOWNLOAD NOW" link or obfuscate it.  It's in a <script>
        # block right after the download link.
        my $script = $dom.find('a#dlbutton + script')[0];

        # The script does a thing like this:
        #   document.getElementById('dlbutton').href = "/d/RjdUFwva/" + (518720 % 51245 + 518720 % 913) + "blahblah"
        if $script ~~ /'document.getElementById(\'dlbutton\').href = "' $<baseURL>=<-["]>+
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
        } else {
            die "Didn't find download link"
        }
    }

    method do-download-file($client, $dl-uri) {
        say "Downloading from $.url =>  file $dl-uri";
        my $response = await $client.get($dl-uri);
        my $fh = open self.pathname, :w, :bin;

        react {
            whenever $response.body-byte-stream -> $chunk {
                $fh.write($chunk);
            }
        }

        say "Done downloading $dl-uri";
        $fh.close;
    }

    method Xdo-download-file($client, $dl-uri) {
        say "Downloading from $.url =>  file $dl-uri";
        my 
        react {
            whenever $client.get($dl-uri) -> $response {
                my $fh = open self.pathname, :w, :bin;
                whenever $response.body-byte-stream -> $chunk {
                    $fh.write($chunk);
                }
                LAST {
                    say "Done downloading $dl-uri";
                    $fh.close;
                }
            }
        }
    }

    method gist { "download-from($.url)" }
}
