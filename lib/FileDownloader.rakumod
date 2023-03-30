use Cro::HTTP::Response;
use Cro::HTTP::Client;
use Cro::Uri;

# Represents when there are too many concurrent downloads from a source
# and we should try another
#class X::FileDownloader::SourceBandwidthExceeded { }

constant $user-agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0';

role FileDownloader {

    has Str $.filename is required;
    has Str $.url is required;
    has Pair @!dl-headers;
    has Cro::HTTP::Client $.client = .new(:http<1.1>);  # KrakenFiles has bad thruput with http/2, and GoFile requires it for downloads

    method pathname { 'working/' ~ $.filename }
    method gist { "download-from($.url)" }
    method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) { ... }

    method run {
        say "Trying to download file from $.url";
        react {
            my $url = Cro::Uri.parse($.url);
            whenever $.client.get($url, user-agent => $user-agent) -> $response {
                if $response.content-type.type-and-subtype eq 'text/html'
                    or
                   $response.content-type.type-and-subtype eq 'application/json'
                {
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
        my $start-time = now;

        my $response = await $.client.get($dl-uri, user-agent => $user-agent, headers => @!dl-headers);
        self.pathname.IO.dirname.IO.mkdir;
        my $fh = open self.pathname, :w, :bin;

        my $progress-timer = Supply.interval(30, 10);
        my $bytes = 0;
        react {
            whenever $response.body-byte-stream -> $chunk {
                #say "read { $chunk.elems } bytes";
                $bytes += $chunk.elems;
                $fh.write($chunk);
                LAST {
                    $fh.close;
                    done;
                }
            }
            whenever $progress-timer {
                self.say-progress(message => 'In progress:', bytes => $bytes, start-time => $start-time);
            }
        }

        self.say-progress(message => 'Done Downloading', bytes => $bytes, start-time => $start-time);
    }

    method say-progress(:$message, :$start-time, :$bytes) {
        my $KB = $bytes / 1024;
        my $MB = $KB / 1024;
        my $k-per-sec = $KB / ( now - $start-time).Int;
        printf("%s $.filename %0.2f MB %0.2f KB/s\n", $message, $MB, $k-per-sec);
    }
}
