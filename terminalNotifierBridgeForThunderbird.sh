#!/bin/bash
#
# Scroll down and set the User Configuration Settings before using.
#
##### INTRODUCTION #####
#
# I previously used this to receive calls from TB's Mailbox Alert plugin and display clickable alerts in Terminal-Notifier.app for MacOS <https://github.com/julienXX/terminal-notifier>. It should still work for that purpose, but the plugin hasn't been updated to work with TB 115 as of this writing.
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
# Clicking the alerts will open the email directly in Thunderbird.
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
# This code is (c) 2023-2024 Michael Kupietz and covered by the GPL 3.0 or later license, included in a companion file in this repo. Any use requires the accompanying license file to be included. 
#
##### TROUBLESHOOTING NOTE:
#####
##### A note if you get the "bad interpreter" error while testing this in Terminal,  
##### the Filtaquilla action mysteriously starts failing or giving errors,
##### or, if this script stops working and there is no clear explanation:
##### cd into this script's directory in Terminal and do: 
#####    xattr -l terminalNotifierBridgeForThunderbird.sh
##### if you see com.apple.quarantine listed in the output, do: 
#####    xattr -d com.apple.quarantine terminalNotifierBridgeForThunderbird.sh 
##### MacOS, among its many wonderful surprises, sometimes "quarantines" things  
##### without warning and without giving you clear indication afterwards that it has.
##### In my experience, sometimes when you do the above, soon it's quarantined again,
##### so keep an eye out and don't assume you'll only need to do that once.
#####
#####  
#
# Update history
# 2024feb29 Started keeping track of updates history. Fixed bug where wrong date was hardcoded into date checking, resulting in notifications never firing.
# 2024apr21 Disabled some of the ps functions that were creating unreadably long logs when overlyVerboseDebugging was true, added noNotifcationsForFolders array to skip notifications for emails in certain folders since evidentally Thunderbird is too stoopit to understand when a filter is told not to run on a certain folder 
# 2024apr21#2 add what command string would have been to info logged if prohibited folder found
# 2024may16 improved discernment of whether Betterbird is running... previously it wasn't filtering for other terminal-notifier instances referring to it in parameters. Also update to search running processes by executable paths defined in settings at top. 

###### USER CONFIGURATION: #####

# set these to the paths to your Terminal-Notifier, Thunderbird, and Betterbird (if applicable) apps:
pathToTerminalNotifierApp="/Applications/terminal-notifier.app"
pathToThunderbird="/Applications/Thunderbird.app"
pathToBetterbird="/Applications/Betterbird.app"

#Specify folder names NOT to show notifications for (IE Trash, Spam) in case these aren't filtered out by your calling filter in Thunderbird—or they are, but Thunderbird has a mind of its own and ofter doesn't really do what you tell it to. 
noNotifcationsForFolders=("Spam","Trash")

# Prevent duplicate notifications for the same email in the same folder? (It only looks back across the last 1000 email notifications for purposes of finding dupes. It considers folders, so if an email has moved to a different folder, a new notification for it will not be considered a duplicate.)
prohibitDupes=false

#Keep a logfile showing just the last parameters sent, replacing the entire logfile with each new call to this script, rather than just tacking a log entry onto the bottom of the previous ones
onlyLogLastParametersSent=false

#Length to trim log at.
loglinelimit=5000

#Following is a regular expression to indicate senders who should receive additional alerts via Applescript to make sure they're not missed. This is because MacOS's notifications suck mightily and I want to make absolutely sure I don't miss certain people's emails. set the following to "" to disable this functionality.
urgentSendersRegex=".*@urgentsenderdomain.com|jane@doe.com|roger@rjakes.com"

#Following turns on a lot of logging for debugging. Maybe make the log length longer when this is on, because it creates so much more info a lot gets cut off!
#I used to have it turn off the limit entirely when this was on, but that created such huge logs the script eventually failed.
overlyVerboseDebugging=true

###### END USER CONFIGURATION #####

sessID=$(echo $$)
thedate=0
while getopts s:d:t:j:f:u: flag
do
echo "trying ${flag}"
    case "${flag}" in
        s) thesender=${OPTARG};;
        d) thedate=${OPTARG};;
        t) thetime=${OPTARG};;
        j) thesubject=${OPTARG};;
        f) thefolder=${OPTARG};;
        u) themsg_uri=${OPTARG};;           
#not really using it        g) thegroup=${OPTARG}};;
    esac
done

if [ ! -n "${thefolder}" ]
then
     theorigfolder="no folder originally passed"
     thefolder=${thefolder:=$(basename "$themsg_uri" | sed -e "s/[#0-9]*$//g")}
else
     theorigfolder="${thefolder}"
fi

# that's right, it seems like the folder isn't always sent correctly (or ever) by Mailbox Alert so we'll parse it from the uri. 
# Updated 2023oct10 to check and see if it's been set by a flag before parsing from URI, since FiltaQuilla author seems like he's going to add foldername as a passable token in javascript actions


if [[ ${noNotifcationsForFolders[@]} =~ $thefolder ]]
then
  skipNotification=true
else
  skipNotification=false
fi

if [ $onlyLogLastParametersSent == true ]
then
     echo "$(date) - parameters received -s \"$thesender\" -d \"$thedate\" -t \"$thetime\" -j \"$thesubject\" -f \"$thefolder\" -u \"$themsg_uri\" -f \"$thefolder\"" > ~/.terminalNotifierForThunderbird/parameters.log
else
     echo "$(date) - parameters received -s \"$thesender\" -d \"$thedate\" -t \"$thetime\" -j \"$thesubject\" -f \"$thefolder\" -u \"$themsg_uri\"  -f \"$thefolder\"" >> ~/.terminalNotifierForThunderbird/parameters.log
fi

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

# check for betterbird. Just ignore this section if you're a glutton for punishment and don't use betterbird. Don't remove it, though, Thunderbird needs it too.

if [ $overlyVerboseDebugging == true ]
then
     echo '. ' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '.. ' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '... ' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '.... ' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '..... ' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) ##### STARTING NEW EMAIL at ${date}, DUDE ##### ." >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) ##### STARTING NEW EMAIL at ${date}, DUDE ##### .." >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) ##### STARTING NEW EMAIL at ${date}, DUDE ##### ..." >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) ##### STARTING NEW EMAIL at ${date}, DUDE ##### ...." >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) ##### STARTING NEW EMAIL at ${date}, DUDE ##### ....." >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) ##### parameters received -s \"$thesender\" -d \"$thedate\" -t \"$thetime\" -j \"$thesubject\" -f \"$thefolder\" -u \"$themsg_uri\"  -f \"$thefolder\"" >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '$(sessID) #####dumping env: ' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     env >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '$(sessID) #####Current (which pgrep):' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     which pgrep >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
      echo '$(sessID) #####Current pgrep -fl $pathToBetterbird | grep -v $pathToTerminalNotifierApp | grep -v pgrep):' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     pgrep -fl $pathToBetterbird | grep -v $pathToTerminalNotifierApp | grep -v pgrep >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     #NO! Too much output echo '$(sessID) #####Current ps -o args= $PPID):' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     #NO! Too much output ps -o args= $PPID >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     #NO! Too much output echo '$(sessID) #####Current ps -axMww' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     #NO! Too much output ps -axMww >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo '$(sessID) #####Current (ps -axMww | grep [b]ird | grep -v $pathToTerminalNotifierApp | grep -v pgrep)' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     ps -axMww | grep [b]ird  | grep -v $pathToTerminalNotifierApp | grep -v pgrep >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) #####folder originally passed was: ${theorigfolder}" >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo "$(sessID) #####folder currently set to: ${thefolder}" >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
 fi

findBB=$(pgrep -fli $pathToBetterbird | grep -v $pathToTerminalNotifierApp | grep -v pgrep)
  #for some BASHful reason, probably just to annoy me, 'pgrep betterbird' doesn't work when this script is run by Betterbird or Thunderbird, but does if run from the command line in Terminal. Above does.
          
if [ $findBB ]
            then
                 if [ $overlyVerboseDebugging == true ]
                 then
                      echo "$(sessID) #####betterbird found by pgrep -fli $pathToBetterbird | grep -v $pathToTerminalNotifierApp | grep -v pgrep (output follows)" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
                 
                 fi
                 theAppPath="$pathToBetterbird/Contents/MacOS/betterbird-bin"
                 theAppIcon="file:/$pathToBetterbird/Contents/Resources/betterbird.icns"
            else
                 if [ $overlyVerboseDebugging == true ]
                 then
                      echo "$(sessID) #####betterbird not found by pgrep -fli $pathToBetterbird | grep -v $pathToTerminalNotifierApp | grep -v pgrep (output follows)" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
                 fi
                 theAppPath="$pathToThunderbird/Contents/MacOS/thunderbird-bin"
                 theAppIcon="file:/$pathToThunderbird/Contents/Resources/thunderbird.icns"
            # removed -group "$themsg_uri" , shouldn't need it now
fi
       if [ $overlyVerboseDebugging == true ]
                 then
                  echo '$(sessID) #####Above based on current pgrep -fli $pathToBetterbird | grep -v $pathToTerminalNotifierApp | grep -v pgrep:' >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
     echo $findBB >> ~/.terminalNotifierForThunderbird/emailnotifications.log 2>&1
  fi
#end check for betterbird

if [ -n "${thefolder}" ]
then
    if $prohibitDupes && grep -Fq "$themsg_uri" ~/.terminalNotifierForThunderbird/emailnotifications.log
    then
        echo "~A~ $(date): NO NOTIFICATION, dupe found. thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
    else
         if $skipNotification
         then
              echo "~A2~ $(date): NO NOTIFICATION, prohibited folder found. theorigfolder: $theorigfolder, thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log         
              if [ $overlyVerboseDebugging == true ]
              then
                   echo "~A3~ $(date):  command string would have been " "$pathToTerminalNotifierApp"/Contents/MacOS/terminal-notifier -title \"$thesender $thedate $thetime\" -subtitle \"$thesubject\" -message \"$thefolder\" -execute \"$theAppPath -mail \\\"$themsg_uri\\\"\" -appIcon \"$theAppIcon\" 
              fi 
         else
             datediff=$(echo "($(date +%s) - $(date -j -f "%a %b %d %Y %H:%M:%S GMT%z" "$thedate" "+%s")) / 3600 / 24"|bc)
             if [[ $datediff -lt 30 ]]
             then
                 #only notify for emails dated within the last 30 days because fucking Thunderbird is stoopit.
                 echo "~B~ $(date): Notifying. thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
                 if [ $overlyVerboseDebugging == true ]
                 then
                     echo "command string " "$pathToTerminalNotifierApp"/Contents/MacOS/terminal-notifier -title \"$thesender $thedate $thetime\" -subtitle \"$thesubject\" -message \"$thefolder\" -execute \"$theAppPath -mail \\\"$themsg_uri\\\"\" -appIcon \"$theAppIcon\" 
                 fi 
                 #run that puppy.
                 "$pathToTerminalNotifierApp"/Contents/MacOS/terminal-notifier -title "$thesender $thedate $thetime" -subtitle "$thesubject" -message "$thefolder" -execute "$theAppPath -mail \"$themsg_uri\"" -appIcon "$theAppIcon"
             else
                 echo "~C~ $(date): Not Notifying because date is over 30 days ago. datediff: $datediff thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
             fi
         fi
    fi
else
    echo "~D~ $(date): NO FOLDER SPECIFIED thesender: $thesender, thedate: $thedate, thetime: $thetime, thesubject: $thesubject, thefolder: $thefolder, themsg_uri: $themsg_uri" >> ~/.terminalNotifierForThunderbird/emailnotifications.log
fi

#Urgent Senders. ignore this section if you haven't specified $urgentSendersRegex

if [[ $thesender =~ $urgentSendersRegex ]] 
then 
 if [ $overlyVerboseDebugging == true ]
            then
                echo '~E1~ osascript command string' osascript -e "display notification \"IMPORTANT"'!'"\" with title \"$thesubject\" subtitle \"$thesender\" sound name \"Frog\"" -e "tell application \"Finder\"" -e "activate" -e "display dialog (\"Important email"'!'" Subject: $thesubject from $thesender\") buttons {\"Open\"} default button 1"  -e "end tell"\; "$theAppPath -mail \"$themsg_uri\""  >> ~/.terminalNotifierForThunderbird/emailnotifications.log
            fi 
	(osascript -e "display notification \"IMPORTANT"'!'"\" with title \"$thesubject\" subtitle \"$thesender\" sound name \"Frog\"" -e "tell application \"Finder\"" -e "activate" -e "display dialog (\"Important email"'!'" Subject: $thesubject from $thesender\") buttons {\"Open\"} default button 1"  -e "end tell";
	"$theAppPath -mail \"$themsg_uri\"") &
fi

#end urgent senders

#if [ ! $overlyVerboseDebugging == true ] ## NO See notes at top, this caused problems from the giant log files if I forgot to turn overlyVerboseDebugging back off.
#then
     echo "$(tail -$loglinelimit ~/.terminalNotifierForThunderbird/emailnotifications.log | sed -E 's/^   [0-9]+ //' | uniq -c)" > ~/.terminalNotifierForThunderbird/emailnotifications.log.tmp
     # tail to limit to 1000 lines, then sed to remove dupe total readout left by previous uniq, then dedupe with uniq
#fi
mv ~/.terminalNotifierForThunderbird/emailnotifications.log.tmp ~/.terminalNotifierForThunderbird/emailnotifications.log
rm -Rf ~/.terminalNotifierForThunderbird/emailnotifications.log.tmp
# if you read and write from a single file at the same time, you can get unlucky and get a race condition where it writes before it's done reading, erasing the file. 
rm  -fR ~/.terminalNotifierForThunderbird/emailNotifierlockfile
