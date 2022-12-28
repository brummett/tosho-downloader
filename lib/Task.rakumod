unit class Task;

has Channel $.queue;
has $.is-done is rw = False;

method run { ... }

method done { $.is-done = True }
