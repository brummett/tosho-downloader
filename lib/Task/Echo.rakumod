use Task;

unit class Task::Echo is Task;

has $.message;

method run {
    say "Echo: $.message";
    await Promise.in(10);
    say "Task done: $.message";
    self.done;
}

method gist { "Echo($.message)" }


