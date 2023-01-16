use Cro::HTTP::Response;
use Cro::HTTP::Client;
use Cro::Uri;

unit role FileDownloader;

has Str $.filename;
has Str $.url;

method pathname { 'working/' ~ $.filename }
method gist { "download-from($.url)" }
method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) { ... }

method run {
    say "Trying to download file from $.url";
    react {
        my $client = Cro::HTTP::Client.new();
        my $url = Cro::Uri.parse($.url);
        whenever $client.get($url) -> $response {
            if $response.content-type.type-and-subtype eq 'text/html' {
                my $dl-uri = self.get-download-link($response);
                self.do-download-file($client, $dl-uri);
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

method do-download-file($client, $dl-uri) {
    say "Downloading from $.url =>  file $dl-uri";
    my $response = await $client.get($dl-uri);
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
