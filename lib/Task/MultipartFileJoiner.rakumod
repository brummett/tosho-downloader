use Task;
use Gcrypt::Simple :MD5;

unit class Task::MultipartFileJoiner is Task;

has Str $.filename;
has Task @.file-part-tasks;
has Str $.md5;

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

    my $final-fh;
    if @.file-part-tasks.elems > 1 {
        # Join all the parts together here
        $final-fh = open $.filename, :w, :bin;
    }

    my $md5 = MD5;
    for @.file-part-tasks -> $task {
        say "  ",$task.pathname;
        react {
            whenever $task.pathname.IO.open(:r, :bin).Supply -> $chunk {
                $md5.write($chunk);
                $final-fh.write($chunk) if $final-fh;
            }
        }
    }
    $final-fh.close if $final-fh;

    say "  ==> $.filename";

    if @.file-part-tasks.elems == 1 {
        # just one part, move the file
        say "  was just one part.  Moving to $.filename";
        rename @.file-part-tasks[0].pathname, $.filename, :createonly;
    } else {
        unlink $_.pathname for @.file-part-tasks;
    }

    if $md5.hex ne $!md5 {
        note "****   $.filename md5 differs!!\n        Got      { $md5.hex }\n        Expected $!md5";
        my $dirname = $.filename.IO.dirname;
        my $basename = $.filename.IO.basename;
        rename $.filename, "{$dirname}/badsum-{$basename}";
    }
    self.done;
}

method gist {
    "Joiner for $.filename: { @.file-part-tasks.elems } parts";
}
