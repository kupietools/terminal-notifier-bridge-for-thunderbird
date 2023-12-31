#!/bin/bash

# I previously used this to receive calls from TB's Mailbox Alert plugin and display clickable alerts in Terminal-Notifier.app for MacOS <https://github.com/julienXX/terminal-notifier>. It should still work for that purpose, but the plugin hasn't been updated to work with TB 115 as of this writing.
#
# Clicking the alerts will open the email directly in Thunderbird.
#
# This script accepts the following command line flags specifying info which the notification will display:
#        -s sender
#        -d date
#        -t time
#        -j subject
#        -f mail folder (this will be parsed from the message URI if not supplied explicitly)
#        -u mail message URI (this is not displayed, but is needed to have clicking on the alert open the message in TB.  
#
# This bridge can be used with FiltaQuilla's "Run Application" filter action by specifying the following line (minus the beginning # mark) as the application for the action to run:
# /path/to/terminalNotifierBridgeForThunderbird.sh,-j,@SUBJECT@,-u,@MESSAGEURI@,-s,@AUTHOR@,-d,@DATE@
# (Note: Once FiltaQuilla's javascript actions is updated with @FOLDERNAME@, as seems imminent as of this posting, you can also add ,-f,@FOLDERNAME@ to the end of that line. 
#
# See the readme.md in the original github repo this is from for fuller information: https://github.com/kupietools/terminal-notifier-bridge-for-thunderbird/
#
# Just so you are aware, this script creates an invisible folder called .terminalNotifierForThunderbird in your home directory, for purpose of tracking dupes and keeping a lockfile to prevent simultaneously executing more than once at a time. You can safely delete this folder at any time, although if you choose to prohibit duplicate notifications in the settings below, you will reset the duplicate tracking by deleting it and the next appearance of any subsequent notification will never register as a dupe.
#
# Be excellent to each other. 
#
# Michael Kupietz
# FileMaker, Web, and IT Support consulting: https://kupietz.com
# Personal site: https://michaelkupietz.com
#
# This code is (c) 2023 Michael Kupietz and covered by the GPL 3.0 or later license, included in a companion file in this repo. Any use requires the accompanying license file to be included. 

###### USER CONFIGURATION: #####

# set these to the paths to your Terminal-Notifier and Thunderbird apps:
pathToTerminalNotifierApp="/Applications/terminal-notifier.app"
pathToThunderbird="/Applications/Thunderbird.app"

# Prevent duplicate notifications for the same email in the same folder? (It only looks back across the last 1000 email notifications for purposes of finding dupes. It considers folders, so if an email has moved to a different folder, a new notification for it will not be considered a duplicate.)
prohibitDupes=false;

# Uncomment the following line to save the latest parameters received to ~/.terminalNotifierForThunderbird/parameters.log (for testing purposes only)
echo "$@" > ~/.terminalNotifierForThunderbird/parameters.log


###### END USER CONFIGURATION #####

thedatein=0
while getopts s:d:t:j:f:u: flag
do
echo "trying ${flag}"
    case "${flag}" in
        s) thesender=${OPTARG};;
        d) thedatein=${OPTARG};;
        t) thetime=${OPTARG};;
        j) thesubject=${OPTARG};;
        f) thefolder=${OPTARG};;
        u) themsg_uri=${OPTARG};;           
#not really using it        g) thegroup=${OPTARG}};;
    esac
done

thefolder=${thefolder:=$(basename "$themsg_uri" | sed -e "s/[#0-9]*$//g")}
# that's right, it seems like the folder isn't always sent correctly (or ever) by Mailbox Alert so we'll parse it from the uri. 
# Updated 2003oct10 to check and see if it's been set by a flag before parsing from URI, since FiltaQuilla author seems like he's going to add foldername as a passable token in javascript actions

mkdir -p ~/.terminalNotifierForThunderbird/

count=0

# use a lockfile to make sure TerminalNotifier isn't launched more than once at a time

until [[ ! -f  ~/.terminalNotifierForThunderbird/emailNotifierlockfile ]]
do
    sleep 1
    count=$count+1
    if  [[ $count -gt 30 ]]
    then 
    #lockfile in place more than 30 seconds, something's wrong, just delete it. 
    rm -fR ~/.terminalNotifierForThunderbird/emailNotifierlockfile
    fi
done

trap 'rm -fR ~/.terminalNotifierForThunderbird/emailNotifierlockfile; exit $?' INT TERM EXIT
echo "$(date)" > ~/.terminalNotifierForThunderbird/emailNotifierlockfile

if [ -n "${thefolder}" ]
then
    if $prohibitDupes && grep -Fq "$themsg_uri" ~/.terminalNotifierForThunderbird/emailnotifications.log
then

echo "$(date): NO NOTIFICATION, dupe found. thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log

else

    echo "$(date): Notifying. thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log

    #run that puppy.

    "$pathToTerminalNotifierApp"/Contents/MacOS/terminal-notifier -title "$thedate $thesender $thetime" -subtitle "$thedate $thesubject" -message "$thefolder" -execute "$pathToThunderbird/Contents/MacOS/thunderbird-bin -mail \"$themsg_uri\"" -appIcon "file://$pathToThunderbird/Contents/Resources/thunderbird.icns"
    # removed -group "$themsg_uri" , shouldn't need it now

fi
else
    echo "$(date): NO FOLDER SPECIFIED thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
fi

echo "$(tail -1000 ~/.terminalNotifierForThunderbird/emailnotifications.log | sed -E 's/^   [0-9]+ //' | uniq -c)" > ~/.terminalNotifierForThunderbird/emailnotifications.log.tmp
# tail to limit to 1000 lines, then sed to remove dupe total readout left by previous uniq, then dedupe with uniq

mv ~/.terminalNotifierForThunderbird/emailnotifications.log.tmp ~/.terminalNotifierForThunderbird/emailnotifications.log
rm -Rf ~/.terminalNotifierForThunderbird/emailnotifications.log.tmp

# if you read and write from a single file at the same time, you can get unlucky and get a race condition where it writes before it's done reading, erasing the file. 

rm  -fR ~/.terminalNotifierForThunderbird/emailNotifierlockfile
