<!-- name: Workspaces and invitations -->
<!-- desc: several teams or customers in one app: data kept apart, invitations, members, leaving -->
<!-- for: all -->
<!-- needs: accounts roles -->

## Requirements

### Workspaces

The system must keep the data of each workspace apart from every other workspace.

- Given a person in several workspaces, when they switch, then they see only the data of the workspace they are in
- Given any request, when it reads or changes data, then it only reaches data of the workspace it was made in
- Given a new account, when it signs in for the first time, then it creates a workspace or joins the one it was invited to

### Invitations

The system must let members invite people to a workspace by email.

- Given a member allowed to invite, when they invite an email, then that person gets an email with a link that expires
- Given an invitation link, when the invited person opens it, then they join the workspace with the role chosen in the invitation (creating an account first if they have none)
- Given a pending invitation, when the inviter cancels it, then its link stops working

### Members

The system must let the people allowed to do so see and manage the members of a workspace.

- Given the members screen, when it opens, then it lists every member with their role and pending invitations
- Given a member, when an administrator removes them, then they lose access to the workspace at once and their content stays in it
- Given a member, when they leave the workspace, then they lose access and the workspace keeps their content

## Edge cases

- [Invitations] An invitation sent to an email that is already a member: no second membership, they are told they are in
- [Members] The last administrator tries to leave: refused until someone else is an administrator
- [Workspaces] A link to an item of another workspace: it says the item is not available, never shows it

## Open questions

- [Workspaces] Can one account belong to several workspaces?
- [Invitations] How long does an invitation link last?
- [Members] What happens to a workspace when its last member leaves or its owner deletes their account?
