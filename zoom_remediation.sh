#!/bin/sh

killall ZoomOpener

killall RingCentralOpener

defaults write /Library/Preferences/us.zoom.config.plist ZDisableVideo 1

# Loop start

for targetFolder in `ls /Users | grep -v Shared | grep -v Guest | grep -v .localized | grep -v .DS_Store | grep "[A-z 0-9]"`; do

	if [[ -d /Users/$targetFolder/.zoomus/ ]]; then
               rm -Rf /Users/$targetFolder/.zoomus/
                    # Remove ZoomOpener folder
	fi

		touch /Users/$targetFolder/.zoomus
        	chmod 000 /Users/$targetFolder/.zoomus
                    # Create flat file to prevent reinstallation
                    
	if [[ -d /Users/$targetFolder/.ringcentralopener/ ]]; then
               rm -Rf /Users/$targetFolder/.ringcentralopener/
                    # Remove RingCentralOpener folder
	fi
	
               touch /Users/$targetFolder/.ringcentralopener
               chmod 000 /Users/$targetFolder/.ringcentralopener
                    # Create flat file to prevent reinstallation

done

exit 0
