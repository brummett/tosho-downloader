use FileDownloader;
use Task;

class Task::ToshoDownload is Task {

    class X::FileDownloadSources::NoSupportedSources is Exception {
        has Str $.name;
        method message { "$!name has no supported sources" }
    }

    # This class represents one file to be download with one or more sources,
    # and each source has one or more parts.
    # It has a mechanism for picking which source to download from.
    class FileDownloadSources {
        use Task::ZippyDownloader;

        # The name for this file
        has Str $.filename is required;

        # pathname on the local system to download to, same as filename unless it's part of a batch
        has Str $.download-pathname is required;

        # keys are download site names, values are a list of URLs. Comes from the 'links' key of one of the files
        has %.alternatives is required;

        submethod BUILD(:$!filename, :$!download-pathname, :%!alternatives) {
            unless %!alternatives<ZippyShare>:exists {
                die X::FileDownloadSources::NoSupportedSources.new(name => $!filename);
            }
        }

        # Pick one of the sources and return a list of downloader Tasks from the
        # supported sources
        method get-download-tasks {
            say "Picking source for $.filename...";

            # when there's only one link, it's a plain string rather than a list of one item
            my @zippy-links = %!alternatives<ZippyShare> ~~ Str ?? [  %!alternatives<ZippyShare> ] !! %!alternatives<ZippyShare>.List;
            say "    There are { @zippy-links.elems } Zippy links";

            my $part-num = 1;
            my @dl-tasks = @zippy-links.map({
                                Task::ZippyDownloader.new(
                                    filename => sprintf('%s.%03d', $!download-pathname, $part-num++),
                                    url => $_)
                            });
            say "    There are { @dl-tasks.elems } download tasks";
            return @dl-tasks;
        }
    }

    # Download torrent ID from animetosho's feed API
    # and queue download tasks for each part of each file

    has Int $.id is required;
    has Str $.name is required;

    use Cro::HTTP::Client;

    use Task::MultipartFileJoiner;

    my $client = Cro::HTTP::Client.new(base-uri => 'https://feed.animetosho.org/json',
                                       :http<1.1>,
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
        my $dl-sources = FileDownloadSources.new(filename          => $file<filename>,
                                                 download-pathname => $file<filename>,
                                                 alternatives      => $file<links>,
                                                );
        self.queue-download-one-of-the-files(filename   => $file<filename>,
                                             md5        => $file<md5>,
                                             dl-sources => $dl-sources);
        CATCH {
            when X::FileDownloadSources::NoSupportedSources {
                $*ERR.say: "***** ",$_;
            }
        }
    }

    # This page is for downloading multiple files grouped together. Each file
    # might be split into parts
    method queue-download-multiple-files(Str $title, @files) {
        for @files -> $file {
            my $final-filename = IO::Spec::Unix.catpath($, $title, $file<filename>);
            my $dl-sources = FileDownloadSources.new(filename           => $file<filename>,
                                                     download-pathname  => $final-filename,
                                                     alternatives        => $file<links>,
                                                    );
            self.queue-download-one-of-the-files(filename   => $final-filename,
                                                 md5        => $file<md5>,
                                                 dl-sources => $dl-sources);

            CATCH {
                when X::FileDownloadSources::NoSupportedSources {
                    $*ERR.say: "***** ",$_;
                }
            }
        }
    }

    method queue-download-one-of-the-files(Str :$filename, Str :$md5, FileDownloadSources :$dl-sources) {
        my @dl-tasks is Array[FileDownloader] = $dl-sources.get-download-tasks();
        say "\t$filename: { @dl-tasks.elems } parts";

        $.queue.send($_) for @dl-tasks;
        $.queue.send(Task::MultipartFileJoiner.new(filename => $filename,
                                                   file-part-tasks => @dl-tasks,
                                                   md5 => $md5,
                                                   queue => self.queue));
    }

    method gist { "Task::ToshoDownload(name => $.name, id => $.id)" }
}
