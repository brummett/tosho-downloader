use Task;

unit class Task::ToshoDownload is Task;

# Download torrent ID from animetosho's feed API
# and queue download tasks for each part of each file

has Int $.id;
has Str $.name;

use Cro::HTTP::Client;

use Task::FileDownloader;
use Task::MultipartFileJoiner;

my $client = Cro::HTTP::Client.new(base-uri => 'https://feed.animetosho.org/json',
                                   timeout => { connection => 10, headers => 10 });

method run {
    say "Trying to get tosho id $.id from feed API";

    my $num-retries = 5;

    while $num-retries > 0 {
        my $response = await $client.get('', query => { show => 'torrent', id => $.id });
        say "Got response for $.id, status { $response.status }";
        my $data = await $response.body();

        # status can be "complete", "skipped", "processing"
        if $data<status> ne 'complete' {
            say "$data<title> is not yet complete: $data<status>";
            self.done;
            return;
        }

        if $data<num_files> == 1 {
            self.queue-download-single-file($data<files>[0]);
        } else {
            self.queue-download-multiple-files($data<title>, $data<files>);
        }

        CATCH {
            when X::Cro::HTTP::Client::Timeout {
                $*ERR.say: "***** Timeout when getting $.name id $.id: $_";
                $num-retries--;
                redo;
            }
            default {
                $*ERR.say: "\n\n****** Caught exception { $_.^name } getting $.id: ",$_;
                last;
            }
        }

        self.done;
        return;
    }
}

# This page is for downloading a single-file, perhaps split into parts
method queue-download-single-file($file) {
    if $file<links><ZippyShare>.elems < 1 {
        die "**** $file<filename> has no ZippyShare links";
    }

    self.queue-download-one-of-the-files(filename => $file<filename>,
                                         md5 => $file<md5>,
                                         zippy-share-links => $file<links><ZippyShare>);
}

# This page is for downloading multiple files grouped together. Each file
# might be split into parts
method queue-download-multiple-files(Str $title, @files) {
    for @files -> $file {
        if $file<links><ZippyShare>.elems < 1 {
            die "**** $file<filename> has no ZippyShare links";
        }

        self.queue-download-one-of-the-files(filename => $file<filename>,
                                             md5 => $file<md5>,
                                             zippy-share-links => $file<links><ZippyShare>,
                                             title => $title);
    }
}

multi method queue-download-one-of-the-files(Str :$filename, Str :$zippy-share-links, Str :$md5, Str :$title?) {
    self.queue-download-one-of-the-files(:$filename, zippy-share-links => [ $zippy-share-links ], :$md5, :$title)
}

multi method queue-download-one-of-the-files(Str :$filename, :@zippy-share-links, Str :$md5, Str :$title?) {
    say "\t$filename: { @zippy-share-links.elems } parts";

    my $part-num = 1;

    # Multi-file torrents get binned by the title of the whole group
    my $final-filename = $title ?? IO::Spec::Unix.catpath($, $title, $filename) !! $filename;

    my @child-tasks = map { Task::FileDownloader::ZippyShare.new(
                                filename => sprintf('%s.%03d', $final-filename, $part-num++),
                                url => $_,
                                queue => self.queue)
                          }, @zippy-share-links;

    $.queue.send($_) for @child-tasks;
    $.queue.send(Task::MultipartFileJoiner.new(filename => $final-filename,
                                               file-part-tasks => @child-tasks,
                                               md5 => $md5,
                                               queue => self.queue));
}

method gist { "Task::ToshoDownload(name => $.name, id => $.id)" }
