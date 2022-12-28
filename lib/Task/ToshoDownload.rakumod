use Task;

unit class Task::ToshoDownload is Task;

# Download a URL from AnimeTosho for a show or file, parse its contents
# and queue download tasks for each part of each file

has Str $.url;

use Cro::HTTP::Client;
use Cro::Uri;
use DOM::Tiny;

use Task::FileDownloader;
use Task::MultipartFileJoiner;

method run {
    say "Trying to get $.url";
    my $response = await Cro::HTTP::Client.get($.url);

    say "Response for $.url was { $response.status }";
    self.parse-page($response);
    self.done;

    CATCH {
        default {
            $*ERR.say: "\n\n****** Caught exception getting $.url: $_";
        }
    }
}

method Xrun {
    say "Trying to get $.url";
    react {
        my $client = Cro::HTTP::Client.new();
        say "Created client $client";
        my $url = Cro::Uri.parse( $.url );
        say "parsed url $url";
        whenever $client.get($url) -> $response {
            if $response.content-type.type-and-subtype eq 'text/html' {
                self.parse-page($response);
            }
            LAST {
                self.done;
            }
            QUIT {
                default {
                    note "$url failed: " ~ .message;
                }
            }
        }
    }
}

method parse-page($response) {
    say "Got response $response";
    say "status was { $response.status }";
    my $dom = DOM::Tiny.parse(await $response.body);

    if $dom.find('div#content > table').elems == 2 {
        self.queue-download-single-file($dom);
    } else {
        self.queue-download-multiple-files($dom);
    }
}

# This page is for downloading a single-file, perhaps split into parts
method queue-download-single-file($dom) {
    # For a page describing a single file, the download links are in the second table
    my $download-table = $dom.find('div#content > table')[1];
    say "Extracted download-table: $download-table";
    my $filename-link = $download-table.find('tr:first-of-type td a')[0];

    my @zippy-share-links = $download-table.find('tr:nth-child(2) a[href*="zippyshare.com"]');
    say "Got { @zippy-share-links.elems } zippyshare links";

    my $part-num = 1;
    my @child-tasks = map { Task::FileDownloader::ZippyShare.new(
                                filename => sprintf('%s.%03d', $filename-link.text, $part-num++),
                                url => $_.attr('href'),
                                queue => self.queue)
                          }, @zippy-share-links;
    $.queue.send($_) for @child-tasks;

    $.queue.send(Task::MultipartFileJoiner.new(filename => $filename-link.text,
                                               file-part-tasks => @child-tasks,
                                               queue => self.queue));
}

# This page is for downloading multiple files grouped together. Each file
# might be split into parts
method queue-download-multiple-files($dom) {
    my @file-divs = $dom.find('div.view_list_entry');
    say "There are { @file-divs.elems } files on this page";

    for @file-divs -> $file-div {
        my $filename-link = $file-div.find('a[href*="animetosho.org"]')[0];
        my @zippy-share-links = $file-div.find('a[href*="zippyshare.com"]');

        say "\t{ $filename-link.text }: { @zippy-share-links.elems } parts";

        my $part-num = 1;
        my @child-tasks = map { Task::FileDownloader::ZippyShare.new(
                                    filename => sprintf('%s.%03d', $filename-link.text, $part-num++),
                                    url => $_.attr('href'),
                                    queue => self.queue)
                              }, @zippy-share-links;

        $.queue.send($_) for @child-tasks;
        $.queue.send(Task::MultipartFileJoiner.new(filename => $filename-link.text,
                                                   file-part-tasks => @child-tasks,
                                                   queue => self.queue));
    }
}

method gist { "Task::ToshoDownload($.url)" }
