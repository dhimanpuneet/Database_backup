#!/bin/sh
# Description :
#       Shell script to backup a MySql database.
#       The backup is kept localy and automatically sent to a ftp server
# Author : Romain Vigo Benia
# Last update: June - 2012
# --------------------------------------------------------------------------------

echo "==========================="
echo "== MySQL Database Backup =="
echo "==========================="

# Exception method
die () {
    echo >&2 "$@"
    exit 1
}

####
#### INITIALISATION
####
echo "Starting..."
# Database (to backup) credentials
MyUSER=""          # Username
MyPASS=""          # Password
MyHOST=""          # Hostname
MyDB=""            # Database

# FTP credentials
FtpHOST=""      # host
FtpUSER=""      # Username
FtpPASS=""      # Password

# Backup managment
NB_BACKUP_LOCAL=5       # the number of backups to keep localy
NB_BACKUP_REMOTE=3      # the number of backups to keep on the remote server
SRC_DIR="./backups/"    # the local directory for the backup
DEST_DIR="backup/"      # the remote directory for the backup
[ -d "$SRC_DIR" ] || mkdir $SRC_DIR     # create local backup directory if not already existing

# Tools used
MYSQLDUMP="$(which mysqldump)"
GZIP="$(which gzip)"
FTP="$(which ftp)"
[ -n "$MYSQLDUMP" ] || die "mysqldump not found"
[ -n "$GZIP" ] || die "gzip not found"
[ -n "$FTP" ] || die "ftp not found"

####
#### STEP 1 : dump the database
####
echo "Backing up MySQL database..."
NOW="$(date +"%Y-%m-%d_%H-%M-%S")"
BACKUP=$NOW"_$MyDB.gz"
$MYSQLDUMP -h $MyHOST -u $MyUSER -p$MyPASS $MyDB | $GZIP -9 > $SRC_DIR$BACKUP


####
#### STEP 2 : send the backup to the storage device
####
echo "Sending backup to ftp server..."
ftp -n -i $FtpHOST << _EOF_
        user $FtpUSER $FtpPASS
        put "$SRC_DIR$BACKUP" "$DEST_DIR$BACKUP"
        quit
_EOF_


####
#### STEP 3 : Keep the right number of backups localy and remotely
####
echo "Cleaning up... "
# Localy
NB_LOCAL=$(ls -1 "$SRC_DIR" | wc -l)
NB_TO_DEL_LOCAL=$(echo "$NB_LOCAL-$NB_BACKUP_LOCAL" | bc)
for i in $(seq 1 $NB_TO_DEL_LOCAL)
do
        TO_DEL_LOCAL=$(ls "$SRC_DIR"*_"$MyDB".gz | sort -n | head -1)
        rm $TO_DEL_LOCAL
done

# Remotely
ftp -n -i $FtpHOST << _EOF_
        user $FtpUSER $FtpPASS
        cd "$DEST_DIR"
        ls -1 $SRC_DIR"remote_backup_raw.txt"
        quit
_EOF_

more $SRC_DIR"remote_backup_raw.txt" | awk -F" " '{print $9}' > $SRC_DIR"remote_backup.txt"
NB_REMOTE=$(more $SRC_DIR"remote_backup.txt"  | wc -l)
NB_TO_DEL_REMOTE=$(echo "$NB_REMOTE-$NB_BACKUP_REMOTE" | bc)

for i in $(seq 1 $NB_TO_DEL_REMOTE)
do
        TO_DEL=$(head -n 1 $SRC_DIR"remote_backup.txt")   #first line of the file
        ftp -n -i $FtpHOST << _EOF_
                user $FtpUSER $FtpPASS
                delete "$DEST_DIR$TO_DEL"
                quit
_EOF_
        # we delete the first line of the file
        sed 1d $SRC_DIR"remote_backup.txt" > $SRC_DIR"remote_backup2.txt"
        mv $SRC_DIR"remote_backup2.txt" $SRC_DIR"remote_backup.txt"
done

# clean the temp files
rm $SRC_DIR"remote_backup"*

echo "Done..."
