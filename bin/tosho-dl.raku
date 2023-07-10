#!/usr/local/bin/raku

use Worker;
use ToshoFeedSearch;
use Task::ToshoDownload;

sub MAIN(
    Int $workers? = 5,
) {
    # This is used by the file downloader to store files as they're being processed
    mkdir 'working';

    say "hi";
    my $work-queue = Channel.new();
    my $searcher = ToshoFeedSearch.new();

    #my @workers = map { Worker.new(id => $_, queue => $work-queue) }, ^$workers;
    my @workers = do for ^$workers -> $id {
        my $worker = Worker.new(:$id, queue => $work-queue);
        start $worker.run();
        $worker;
    }
    say "created { @workers.elems } workers";

    react {
        whenever $*IN.lines.Supply -> $line {
            my $trimmed = $line.trim;
            say "read line: $trimmed";

            if $trimmed.chars > 1 {
                my $id = $searcher.search-for($trimmed);
                if $id {
                    say "title $trimmed is id $id";
                    my $task = Task::ToshoDownload.new(queue => $work-queue, id => $id, name => $trimmed);
                    $work-queue.send($task);
                }
            }
        }
    }
    say "main, all done!";
}
