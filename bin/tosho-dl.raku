#!/usr/local/bin/raku

use Worker;
use ToshoFeed;
use Task::ToshoDownload;

sub MAIN(
    Int $workers? = 5,
) {
    # This is used by the file downloader to store files as they're being processed
    mkdir 'working';

    say "hi";
    my %feed := TitleToToshoId.new();
    my $work-queue = Channel.new();

    #my @workers = map { Worker.new(id => $_, queue => $work-queue) }, ^$workers;
    my @workers = do for ^$workers -> $id {
        my $worker = Worker.new(:$id, queue => $work-queue);
        start $worker.run();
        $worker;
    }
    say "created { @workers.elems } workers";

    react {
        whenever $*IN.lines.Supply -> $line {
            say "read line: $line";
            my $id = %feed{$line};
            say "title $line is id $id";
            if $id {
                my $task = Task::ToshoDownload.new(queue => $work-queue, id => $id);
                $work-queue.send($task);
            }
        }
    }
    say "main, all done!"
}
