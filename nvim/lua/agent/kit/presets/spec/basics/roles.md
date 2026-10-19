<!-- name: Roles and permissions -->
<!-- desc: who can see and do what: roles, checks on every action, ownership, changes of role -->
<!-- for: all -->
<!-- needs: accounts -->

## Requirements

### Roles

The system must give every account a role that decides what it can see and do.

- Given a new account, when it is created, then it has the default role
- Given an action, when a person whose role does not allow it tries it, then it is refused with a message and nothing changes
- Given an action the role does not allow, when the interface shows it, then it is hidden or disabled with the reason

### Ownership

The system must know who owns each resource and let the owner manage it.

- Given a resource, when it is created, then its creator is its owner
- Given a resource, when someone who is not its owner and whose role does not allow it tries to change or delete it, then it is refused
- Given an owner, when they transfer a resource to another account, then the new owner has full control and the old one keeps only what their role gives

### Changing roles

The system must let the people allowed to do so change the role of an account.

- Given an administrator, when they change someone's role, then the new permissions apply at once, also to sessions already open
- Given the last administrator, when anyone tries to remove their administrator role, then it is refused
- Given a role change, when it happens, then who changed it, from what and to what is recorded

## Edge cases

- [Roles] A request that skips the interface (an API call, a crafted URL) is checked the same way: permissions are enforced on the server
- [Ownership] The owner's account is deleted: their resources are transferred, kept read-only or deleted, as decided below
- [Changing roles] A person loses a permission while a screen that needs it is open: their next action is refused and the screen says why

## Open questions

- [Roles] Which roles exist, and what can each one see and do?
- [Ownership] What happens to a person's resources when their account is deleted?
- [Changing roles] Who can change roles: only administrators, or also owners of a resource for that resource?
