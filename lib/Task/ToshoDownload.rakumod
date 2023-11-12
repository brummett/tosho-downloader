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
        use Task::KrakenDownloader;
        use Task::GofileDownloader;
        use Task::ClickNUploadDownloader;
        use Task::UppitDownloader;
        use Task::DownloadggDownloader;

        # The name for this file
        has Str $.filename is required;

        # pathname on the local system to download to, same as filename unless it's part of a batch
        has Str $.download-pathname is required;

        # keys are download site names, values are a list of URLs. Comes from the 'links' key of one of the files
        has %.alternatives is required;

        my %download-classes = KrakenFiles => Task::KrakenDownloader,
                               GoFile => Task::GofileDownloader,
                               ClickNUpload => Task::ClickNUploadDownloader,
                               Uppit => Task::UppitDownloader,
                               DownloadGG => Task::DownloadggDownloader,
                                ;

        submethod BUILD(:$!filename, :$!download-pathname, :%!alternatives) {
            unless any(%!alternatives{ %download-classes.keys }:exists) {
                die X::FileDownloadSources::NoSupportedSources.new(name => $!filename);
            }
        }

        # Pick one of the sources and return a list of downloader Tasks from the
        # supported sources
        method get-download-tasks {
            say "Picking source for $.filename...";

            my $source = self!pick-download-source;

            # when there's only one link, it's a plain string rather than a list of one item
            my @dl-links = %!alternatives{$source} ~~ Str ?? [  %!alternatives{$source} ] !! %!alternatives{$source}.List;
            say "    There are { @dl-links.elems } $source links";

            my $part-num = 1;
            my @dl-tasks = @dl-links.map({
                                %download-classes{$source}.new(
                                    filename => sprintf('%s.%03d', $!download-pathname, $part-num++),
                                    url => $_)
                            });
            say "    There are { @dl-tasks.elems } download tasks";
            return @dl-tasks;
        }

        # Returns a key in the %alternatives hash for which source to download from,
        # which must be a key in %download-classes
        method !pick-download-source( --> Str) {
            # Intersect what we support and what's available, then pick one
            return (%download-classes (&) %!alternatives).pick;
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
            # "complete_partial" means some but not all files in a group were fetched,
            # probably as part of a manually-triggered download
            if $data<status> ne 'complete' and $data<status> ne 'complete_partial' {
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
            when X::GofileDownloader::NoWebsiteToken {
                $*ERR.say: "***** ",$_;
            }
        }
    }

    # This page is for downloading multiple files grouped together. Each file
    # might be split into parts
    method queue-download-multiple-files(Str $title, @files) {
        for @files -> $file {
            if not $file<links> {
                $*ERR.say: "***** $file<filename> has no download links";
                next;
            }

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
                when X::GofileDownloader::NoWebsiteToken {
                    $*ERR.say: "***** ",$_;
                }
            }
        }
    }

    method queue-download-one-of-the-files(Str :$filename, Str :$md5, FileDownloadSources :$dl-sources) {
        my @dl-tasks is Array[FileDownloader] = $dl-sources.get-download-tasks();
        say "\t$filename: { @dl-tasks.elems } parts";

        my @promises;
        for @dl-tasks -> $dl-task {
            @promises.push($dl-task.is-done);
            $.queue.send($dl-task);
        }

        start {
            await @promises;
            say "All parts of $filename are finished, queueing joiner task";
            $.queue.send(Task::MultipartFileJoiner.new(filename => $filename,
                                                       file-part-tasks => @dl-tasks,
                                                       md5 => $md5,
                                                       queue => self.queue));
        }
    }

    method gist { "Task::ToshoDownload(name => $.name, id => $.id)" }
}
