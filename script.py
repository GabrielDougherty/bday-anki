import subprocess
import json
from datetime import datetime

# Get contacts with birthdays via AppleScript
def get_contacts_with_birthdays():
    script = '''
    tell application "Contacts"
        set contactList to {}
        repeat with aPerson in people
            if birth date of aPerson is not missing value then
                set end of contactList to {name: name of aPerson, birthday: birth date of aPerson}
            end if
        end repeat
        return contactList
    end tell
    '''
    
    result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
    
    bdays = result.stdout.split(',')
    return [{'name': a.split(':')[0], 'birthday': a.split(':')[1]} for a in bdays]

contacts = get_contacts_with_birthdays()

import genanki

# Create a model (card template)
model = genanki.Model(
    1607392319,
    'Birthday Model',
    fields=[
        {'name': 'Question'},
        {'name': 'Answer'},
    ],
    templates=[
        {
            'name': 'Card 1',
            'qfmt': '{{Question}}',
            'afmt': '{{FrontSide}}<hr id="answer">{{Answer}}',
        },
    ])

# Create deck and add notes
deck = genanki.Deck(2059400110, "Birthdays")

for contact in contacts:
    note = genanki.Note(
        model=model,
        fields=[f"When is {contact['name']}'s birthday?",
                contact['birthday'].strftime("%B %d")])
    deck.add_note(note)

# Generate package
genanki.Package(deck).write_to_file('birthdays.apkg')
