use Task;

unit class Task::MultipartFileJoiner is Task;

has Str $.filename;
has Task @.file-part-tasks;

method run {
    for @.file-part-tasks -> $task {
        if not $task.is-done {
            # At least one child is still running.
            # Reschedule myself and check again later
            await Promise.in(1);
            $.queue.send(self);
            return;
        }
    }

    say "All parts of $.filename are done";

    for @.file-part-tasks -> $task {
        if not $task.pathname.IO.e {
            note "*** At least one part of $.filename didn't download: ", $task.pathname;
            self.done;
            return;
        }
    }

    $.filename.IO.dirname.IO.mkdir;

    if @.file-part-tasks.elems == 1 {
        # just one part, move the file
        say "  was just one part.  Moving to $.filename";
        rename @.file-part-tasks[0].pathname, $.filename, :createonly;

    } else {

        # Join all the parts together
        my $final-fh = open $.filename, :w, :bin;
        for @.file-part-tasks -> $task {
            say "  ",$task.pathname;
            react { 
                whenever $task.pathname.IO.open(:r, :bin).Supply -> $chunk {
                    $final-fh.write($chunk);
                }
            }
        }
        $final-fh.close;
        say "  ==> $.filename";

        unlink $_.pathname for @.file-part-tasks;
    }

    self.done;
}

method gist {
    "Joiner for $.filename: { @.file-part-tasks.elems } parts";
}
