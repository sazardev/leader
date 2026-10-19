<!-- name: Chat and direct messages -->
<!-- desc: talking in real time: direct and group conversations, unread state, presence, history, attachments -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: realtime database storage -->
<!-- design: navigation-shell notification-center file-upload-ui -->

## Requirements

### Conversations

The system must let people talk to one person or to a group in a conversation that keeps its history.

- Given two accounts, when one sends a message to the other, then the conversation exists for both and shows the message with who sent it and when
- Given a group conversation, when a member sends a message, then every member sees it in the same order
- Given a conversation, when a person opens it later, then they can scroll back through everything said since they joined

### Unread and presence

The system must tell people what they have not read and who is around.

- Given new messages in a conversation, when I have not opened it, then it shows how many are unread and I can find it at the top of my list
- Given I open a conversation, when I have seen its last message, then it is marked as read for me
- Given a person is writing, when I am in the same conversation, then I see that they are typing

### Attachments

The system must let people send a file or an image inside a message.

- Given a message, when a person attaches a file, then the others can open or download it from the conversation
- Given an attachment that is too large or not allowed, when it is sent, then it is refused with the reason and the text is kept

## Edge cases

- [Conversations] Two messages are sent at the same moment: both arrive and every member sees them in the same order
- [Conversations] A person loses connection while writing: the draft is kept and sent, once, when they are back
- [Conversations] A member is removed from a group: they stop receiving new messages and keep only what they already saw, as decided below
- [Unread and presence] A person has the conversation open in two devices: reading it in one clears the unread count in both
- [Attachments] The person who sent a file loses access to it: the others keep seeing it, as decided below

## Open questions

- [Conversations] Can messages be edited or deleted, by whom, and for how long?
- [Conversations] Who can start a conversation or add people to a group: anyone, or only people who share a workspace or team?
- [Unread and presence] Is presence (online, typing) shown to everyone or can a person hide it?
- [Attachments] Which file types and sizes are allowed, and how long are attachments kept?
