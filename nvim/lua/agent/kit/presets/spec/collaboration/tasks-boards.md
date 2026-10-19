<!-- name: Tasks and boards -->
<!-- desc: work to do: tasks, assignees, status columns, due dates, ordering and filters -->
<!-- for: all -->
<!-- needs: accounts workspaces -->
<!-- tech: database realtime -->
<!-- design: data-tables search-and-filters dialogs empty-states -->

## Requirements

### Tasks

The system must let people write down work and say who does it and by when.

- Given a workspace, when a person creates a task with a title, then it appears in its first status
- Given a task, when it is assigned to a member, then the assignee is shown and can find it among their tasks
- Given a task with a due date, when the date passes and it is not done, then it is shown as overdue

### Board and statuses

The system must show the work by status and let people move it forward.

- Given a board, when a person moves a task to another status, then it shows there for everyone and the move is recorded
- Given a column, when a person reorders tasks inside it, then the order is kept for everyone
- Given a board, when a person adds, renames or removes a status, then the tasks follow as described below

### Finding tasks

The system must let people narrow the tasks to what matters to them.

- Given a board with many tasks, when a person filters by assignee, status, due date or word, then only the matching tasks are shown
- Given a filter, when the person leaves and comes back, then they can get the same view again

## Edge cases

- [Board and statuses] Two people move the same task at the same moment: the last move wins and the other person sees the task jump with a notice
- [Board and statuses] A status is removed while it still has tasks: they are moved to a status chosen by the person, never lost
- [Tasks] The assignee leaves the workspace: their open tasks become unassigned and the people in charge are told
- [Tasks] A task is deleted while another person is editing it: the editor is told and no change is silently lost
- [Finding tasks] A filter matches nothing: the screen says so and offers to clear the filter

## Open questions

- [Board and statuses] Which statuses exist by default, and can a team define its own?
- [Tasks] Can a task have more than one assignee, subtasks or dependencies?
- [Tasks] Do tasks repeat (every week, every month)? If so, what happens when the previous one is not done?
- [Finding tasks] Can people save and share filters as named views?
