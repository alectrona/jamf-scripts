#!/bin/sh
# This script is intended to be used with JAMF Self Service. It will enable SecureToken for the currently logged in user account
# and either add it to the list of to FileVault enabled users or enable FileVault using a Personal Recovery Key.

# Your policy must include script parameters for a SecureToken enabled administrator username and password. For more information
# on using script parameters, please see https://www.jamf.com/jamf-nation/articles/146/script-parameters.

#Jamf Management Account Credentials (passed as parameter 4 & 5)
adminUser="$4"
adminPassword="$5"
#User to remove from FileVault (if applicable, passed as parameter 6)
userName2="$6"

userName1=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Uses AppleScript to prompt the currently logged in user for their account password.

userPassword1="$(/bin/launchctl asuser "$userName1" /usr/bin/osascript -e 'display dialog "Please enter the password for '"$userName1"':" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"

while true
do

    if [[ "$userPassword1" == "" ]]; then
    echo "Status: Password not provided"

userPassword1="$(/bin/launchctl asuser "$userName1" /usr/bin/osascript -e 'display dialog "Please enter the password for '"$userName1"':" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"

    sleep 5
    else
    echo "Password provided."
    break
    fi
done

jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
PROMPT_TITLE="Password Needed For FileVault"
FORGOT_PW_MESSAGE="You made five incorrect password attempts.
Please contact IT for assistance."

# Thanks to James Barclay (@futureimperfect) for this password validation loop.
TRY=1
until /usr/bin/dscl /Search -authonly "$userName1" "$userPassword1" &>/dev/null; do
    (( TRY++ ))
    echo "Prompting $userName1 for their Mac password (attempt $TRY)..."
    userPassword1="$(/bin/launchctl asuser "$userName1" /usr/bin/osascript -e 'display dialog "Sorry, that password was incorrect. Please try again:" default answer "" with title "'"${PROMPT_TITLE//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"
    if (( TRY >= 5 )); then
        echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
        /bin/launchctl asuser "$userName1" "$jamfHelper" \
            -windowType "utility" \
            -title "$PROMPT_TITLE" \
            -description "$FORGOT_PW_MESSAGE" \
            -button1 'OK' \
            -defaultButton 1 \
            -startlaunchd &>/dev/null &
        exit 1
    fi
done
echo "Successfully prompted for $userName1 password."

# Enables SecureToken for the currently logged in user account.
enableSecureToken() {
    sudo sysadminctl -adminUser $userName1 -adminPassword $userPassword1 -secureTokenOn $adminUser -password $adminPassword
}

# Creates a PLIST containing the necessary administrator and user credentials.
createPlist() {
    echo '<?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    <key>Username</key>
    <string>'$adminUser'</string>
    <key>Password</key>
    <string>'$adminPassword'</string>
    <key>AdditionalUsers</key>
    <array>
        <dict>
            <key>Username</key>
            <string>'$userName1'</string>
            <key>Password</key>
            <string>'$userPassword1'</string>
        </dict>
    </array>
    </dict>
    </plist>' > /private/tmp/userToAdd.plist
}

# Adds the currently logged in user to the list of FileVault enabled users.
addUser() {
    sudo fdesetup add -i < /private/tmp/userToAdd.plist
}

# Enables FileVault using a Personal Recovery Key.
enableFileVault() {
    sudo fdesetup enable -inputplist < /private/tmp/userToAdd.plist
}

# Update the preboot role volume's subject directory.
updatePreboot() {
    diskutil apfs updatePreboot /
}

# Deletes the PLIST containing the administrator and user credentials.
cleanUp() {
    rm /private/tmp/userToAdd.plist
}

#

enableSecureToken
createPlist
if [ "$(sudo fdesetup status | head -1)" == "FileVault is On." ]; then
    addUser
else
    enableFileVault
    removeUser
fi
updatePreboot
cleanUp
