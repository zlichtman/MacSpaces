import Foundation

enum MessagesScripts {
    static let discovery = """
    with timeout of 5 seconds
        tell application "Messages"
            set output to {}
            repeat with c in chats
                if (count of output) is 100 then exit repeat
                set members to id of participants of c
                set labels to {}
                repeat with person in participants of c
                    set displayLabel to full name of person
                    if displayLabel is missing value or displayLabel is "" then set displayLabel to name of person
                    if displayLabel is missing value or displayLabel is "" then set displayLabel to handle of person
                    set end of labels to displayLabel
                end repeat
                if (count of members) > 0 then set end of output to {id of c, name of c, members, labels}
            end repeat
            return output
        end tell
    end timeout
    """
    // Every user value is an Apple Event argument, never interpolated into source.
    static let reply = """
    on replyToConversation(chatID, expectedMembers, bodyText)
        with timeout of 5 seconds
            tell application "Messages"
                set matches to every chat whose id is chatID
                if (count of matches) is not 1 then error "Conversation identity changed"
                set targetChat to item 1 of matches
                if (id of participants of targetChat) is not expectedMembers then error "Conversation participants changed"
                send bodyText to targetChat
                return "submitted"
            end tell
        end timeout
    end replyToConversation
    """
    /// Brings up Messages' own Delete Conversation confirmation, but only when its
    /// front window shows one of the expected names; it never confirms the delete.
    static let deleteConfirmation = """
    on askToDelete(expectedNames)
        tell application "Messages" to activate
        delay 0.4
        tell application "System Events"
            tell process "Messages"
                set windowName to ""
                try
                    set windowName to name of front window
                end try
                set shown to false
                repeat with expected in expectedNames
                    if windowName contains (expected as text) then set shown to true
                end repeat
                if not shown then return "mismatch"
                set deleteItem to first menu item of menu 1 of menu bar item "Conversation" of menu bar 1 whose name starts with "Delete Conversation"
                click deleteItem
                return "asked"
            end tell
        end tell
    end askToDelete
    """
}
