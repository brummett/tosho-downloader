#!/usr/local/bin/raku

use Worker;
use Task::Echo;

sub MAIN(
    Int $workers? = 5,
) {
    say "hi";
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
            my $task = Task::Echo.new(queue => $work-queue, message => $line);
            $work-queue.send($task);
        }
    }
    say "main, all done!"
}
