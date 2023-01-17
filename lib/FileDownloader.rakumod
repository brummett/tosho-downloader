use Cro::HTTP::Response;
use Cro::HTTP::Client;
use Cro::Uri;

constant $user-agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0';

role FileDownloader {

    has Str $.filename;
    has Str $.url;
    has Cro::HTTP::Client $.client = .new;

    method pathname { 'working/' ~ $.filename }
    method gist { "download-from($.url)" }
    method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) { ... }

    method run {
        say "Trying to download file from $.url";
        react {
            my $url = Cro::Uri.parse($.url);
            whenever $.client.get($url, user-agent => $user-agent) -> $response {
                if $response.content-type.type-and-subtype eq 'text/html' {
                    my $dl-uri = self.get-download-link($response);
                    self.do-download-file($dl-uri);
                }
                QUIT {
                    default {
                        note "**** $.filename: $url failed: " ~ .message;
                    }
                }
                CATCH {
                    default {
                        note "**** $.filename: $url failed: " ~ .message;
                    }
                }
            }
        }
        say "Download from $.url is done";
        self.done;
    }

    method do-download-file($dl-uri) {
        say "Downloading from $.url =>  file $dl-uri";
        my $response = await $.client.get($dl-uri, user-agent => $user-agent);
        self.pathname.IO.dirname.IO.mkdir;
        my $fh = open self.pathname, :w, :bin;

        react {
            whenever $response.body-byte-stream -> $chunk {
                $fh.write($chunk);
            }
        }

        say "Done downloading $dl-uri";
        $fh.close;
    }
}
