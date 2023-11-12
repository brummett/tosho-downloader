use Cro::HTTP::Response;
use Cro::HTTP::Client;
use Cro::Uri;
use DOM::Tiny;

# Represents when there are too many concurrent downloads from a source
# and we should try another
#class X::FileDownloader::SourceBandwidthExceeded { }

role FileDownloader {

    has Str $.filename is required;
    has Str $.url is required;
    has $!user-agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:108.0) Gecko/20100101 Firefox/108.0';

    has Cro::HTTP::Client $.client = .new(:http<1.1>);  # KrakenFiles has bad thruput with http/2, and GoFile requires it for downloads

    method pathname { 'working/' ~ $.filename }
    method gist { "download-from($.url)" }

    # Take the response from get()ing the link AnimeTosho referred us to, and
    # returns a url that will allow us to download from
    method get-download-link(Cro::HTTP::Response $response --> Cro::Uri) { ... }

    # Takes the uri returned by get-download-link, and performs the request
    # to get the file
    method do-download-request(Cro::Uri $uri --> Promise) { ... }

    method run {
        say "Trying to download file from $.url";

        my $num-retries = 5;
        while $num-retries > 0 {
            my $url = Cro::Uri.parse($.url);
            my $response = await $.client.get($url, user-agent => $!user-agent);
            if $response.content-type.type-and-subtype eq 'text/html'
                or
               $response.content-type.type-and-subtype eq 'application/json'
            {
                my $dl-uri = self.get-download-link($response);
                self.do-download-file($dl-uri);
            }
            CATCH {
                when X::Cro::HTTP::Client::Timeout {
                    note "* Timeout when getting $.filename from $url: " ~ .message;
                    $num-retries--;
                    # This redo dies with the error:
                    # redo without loop construct
                    redo;
                }
                default {
                    note "**** $.filename: $url failed with a { $_.^name } exception: " ~ .message ~ "\n" ~ .backtrace;
                    last;
                }
            }
            last; # exit the while retries loop
        }

        say "Download from $.url is done";
        self.done;
    }

    method do-download-file($dl-uri) {
        say "Downloading from $.url =>  file $dl-uri";
        my $start-time = now;

        my Cro::HTTP::Response $response = await self.do-download-request($dl-uri);
        my $total-size = $response.header('Content-Length');
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
                self.say-progress(message => 'In progress:', bytes => $bytes, start-time => $start-time, total-size => $total-size);
            }
        }

        self.say-progress(message => 'Done Downloading', bytes => $bytes, start-time => $start-time, total-size => $total-size);
    }

    method say-progress(:$message, :$start-time, :$bytes, :$total-size) {
        my $KB = $bytes / 1024;
        my $MB = $KB / 1024;
        my $k-per-sec = $KB / ( now - $start-time).Int;
        my $pct = ($bytes / $total-size) * 100;
        printf("%s $.filename %0.2f MB %0.2f KB/s %0.1f%%\n", $message, $MB, $k-per-sec, $pct);
    }

    # A method used by many downloaders to extract input elements
    method extract-inputs-from-form(DOM::Tiny $form --> Associative) {
        my %inputs = $form.find('input')
                          .map(-> $input { $input.attr('name') => $input.attr('value') });
        return %inputs;
    }

}
