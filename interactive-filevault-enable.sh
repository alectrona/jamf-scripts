#!/bin/bash

# Interactive FileVault Enable

# Enables FileVault interactively by using the credentials of the current logged-in user.
# Alternatively, this script will re-issue a Personal Recovery Key if FileVault is already enabled.

# OPTIONAL: You may also supply a temporary password for the user as parameter 4 in Jamf Pro.
# This is used if you always provision new Macs with temporary passwords for the user to change later.
# This will eliminate the password prompt if the user's password matches the temporary password.

# This script is intended to be used with JAMF Self Service.

# Created by Alectrona

loggedInUser=$( echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil | /usr/bin/awk '/Name :/ && ! /loginwindow/ { print $3 }' )
loggedInUID=$(/usr/bin/id -u "$loggedInUser")
title="Enable FileVault Encryption"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
count="1"
unset userPass demote

# Determine if we need to use the temp password
if [[ -n "$4" ]] && /usr/bin/dscl /Search -authonly "$loggedInUser" "$4" &>/dev/null; then
    echo "Using $loggedInUser's temporary Mac password..."
    userPass="$4"
else
    echo "Temporary password is empty or not correct; skipping."
fi

# If the temp password is not correct, get the logged in user's password via a prompt
if [[ -z "$userPass" ]]; then
    echo "Prompting $loggedInUser for their Mac password..."
    userPass="$(/bin/launchctl asuser "$loggedInUID" /usr/bin/osascript -e 'display dialog "Please enter the password you use to log in to your Mac:" default answer "" with title "'"${title//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"
fi

# Give the user 4 additional times to put get their password correct
until /usr/bin/dscl /Search -authonly "$loggedInUser" "$userPass" &>/dev/null; do
    (( count++ ))
    echo "Prompting $loggedInUser for their Mac password (attempt $count)..."
    userPass="$(/bin/launchctl asuser "$loggedInUID" /usr/bin/osascript -e 'display dialog "Sorry, that password was incorrect. Please try again:" default answer "" with title "'"${title//\"/\\\"}"'" giving up after 86400 with text buttons {"OK"} default button 1 with hidden answer' -e 'return text returned of result')"
    if (( count >= 4 )); then
        echo "[ERROR] Password prompt unsuccessful after 5 attempts. Displaying \"forgot password\" message..."
        /bin/launchctl asuser "$loggedInUID" "$jamfHelper" -windowType "utility" -title "$title" -alignDescription natural -description "Sorry, you've entered an incorrect password $count times. If you have forgotten your password, please contact IT to help." -button1 'OK' -defaultButton 1 -startlaunchd &>/dev/null &
        exit 1
    fi
done 
echo "$loggedInUser's password was validated; continuing."

# Enables FV2 using a Personal Recovery Key
# Or if FV2 is enabled, issue a new Personal Recovery Key
function enable_filevault_or_issue_new_recovery_key () {
    local plist="/private/tmp/userToAdd.plist"

    /usr/bin/defaults write "$plist" Username -string "$loggedInUser"
    /usr/bin/defaults write "$plist" Password -string "$userPass"
    
    if fdesetup status | /usr/bin/grep "Off" > /dev/null ; then
        echo "Enabling FileVault..."
        /usr/bin/fdesetup enable -inputplist < "$plist"
    else
        echo "FileVault is enabled, issuing new recovery key."
        /usr/bin/fdesetup changerecovery -norecoverykey -verbose -personal -inputplist < "$plist"
    fi

    /bin/rm "$plist"
    /usr/sbin/diskutil apfs updatePreboot /
}

# Make sure the logged-in user is an admin
if /usr/sbin/dseditgroup -o checkmember -m "$loggedInUser" admin | grep -q ^no* ; then
    /usr/sbin/dseditgroup -o edit -n /Local/Default -a "$loggedInUser" -t user admin
    echo "Temporarily granted \"$loggedInUser\" admin privileges."
    demote="true"
fi

enable_filevault_or_issue_new_recovery_key

# Demote the logged-in user if we made them an admin
if [[ "$demote" == "true" ]]; then
    /usr/sbin/dseditgroup -o edit -n /Local/Default -d "$loggedInUser" -t user admin
    echo "Removed admin privileges from \"$loggedInUser\"."
fi

exit 0