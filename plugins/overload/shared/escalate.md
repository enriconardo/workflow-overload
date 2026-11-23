# Escalation

The human decides when a step cannot close by itself:

- a loop reaches its third round without converging (a red verify, a review that keeps finding blocking issues);
- you are stuck: verify will not turn green, or the approach does not work;
- a review finding needs a judgment;
- taking in main meets a conflict, or a red that main shows on its own;
- integrate refuses for a reason its message does not tell you to fix.

Explain the problem in a few lines, with what you tried, and offer three choices with your recommendation:

- **retry**: one more round, with the human's guidance. It grants that round only: if it ends without converging, come back here, and so after every later round;
- **skip**: go on accepting the problem, which goes in the commit's body and among the backlog candidates;
- **stop**: the task is suspended; the branch and its journal stay, and the command that runs it (the journal's `command`, `/overload:task` or `/overload:build`) resumes it.

*Skip* is not offered on a red verify, since a red commit stays forbidden. The human may also answer in their own words. Log their choice with `journal.sh log`, and wait for it before going on.
