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
}
