unit class Worker;

use Task;

has Int $.id;
has Channel $.queue;

method run() {
    react {
        say "Worker $.id waiting for work...";
        whenever $.queue -> Task $task {
            say "Worker $.id got a task ", $task;
            $task.run();
            say "Worker $.id done with task ",  $task;
        }
    }
}
