unit class Task;

has Channel $.queue;
has Promise $.is-done = .new;

method run { ... }

method done { $.is-done.keep(True) }
