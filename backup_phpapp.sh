#!/bin/bash

log() {
    local name=$NAME
    if [ "$name" == "" ] ;then
	name=backup_php_app
    fi
    logger -s -t $name "$*"
}

usage() {
    if [ "$1" != "" ] ; then
	local NAME=$1
    fi
    echo "$NAME options"
    echo "$NAME valid options are:"
    echo "[-c|--config] <configuration_file>: Read configuration variables from designated file"
	
}

#############################
# Script internal variables #
#############################

NAME=""
ARCHIVE_NAME=""

##########################
# Mysql database options #
##########################

dbname=""
dbuser=""
dbpass=""
dbcompress="none"

##############################
# Backup directories options #
##############################

declare -a sourcedirs=( )
backupdir=""
filecompress="none"

###############
# FTP options #
###############

ftphost=""
ftpusername=""
ftppassword=""
ftpdir=""

declare -a uploadfiles

####################
# checksum options #
####################

checksum_algorithm="md5"

####################
# Option variables #
####################

keep_files="no"

##############
# initialize #
##############
timestamp=$(date +%Y%m%d-%H%M%S)

##############################################################
# Parse command line arguments and set options appropriately #
##############################################################

# Most of this code is boilerplate from /usr/share/getopt/getopt-parse.bash

# The following command line arguments are recognized
# -c | --config <config_file>

ARGS=$(getopt --options c: \
	--longoptions config: \
       	--longoptions keep-files \
	--longoptions name: \
	--longoptions archive-name: \
	--longoptions dbname: \
	--longoptions dbuser: \
	--longoptions dbpass: \
	--longoptions dbcompress: \
       	--longoptions sourcedir: \
	--longoptions backupdir: \
	--longoptions filecompress: \
	--longoptions ftphost: \
	--longoptions ftpusername: \
	--longoptions ftppassword: \
	--longoptions ftpdir: \
      	-n  "$NAME" -- "$@")

if [ $? != 0 ] ; then 
    log "Error parsing command line arguments"
    log "Terminating..."
    exit 1
fi

eval set -- "$ARGS"

while true ; do
	case "$1" in
		-c|--config) source "$2"; shift 2 ;;
		--keep-files) keep_files="yes"; shift ;;
		--name) NAME="$1"; shift 2 ;;
		--archive-name) ARCHIVE_NAME="$1"; shift 2;;
		--dbname) dbname="$1"; shift 2;;
		--dbpass) dbpass="$1"; shift 2;;
		--dbcompress) dbcompress="$1"; shift 2;;
		--sourcedir) sourcedirs=( ${sourcedirs[@]} "$1" ); shift 2;;
		--backupdir) backupdir="$1"; shift 2;;
		--filecompress) filecompress="$1"; shift 2;;
		--ftphost) ftphost="$1"; shift 2;;
		--ftpusername) ftpusername="$1"; shift 2;;
		--ftppassword) ftppassword="$1"; shift 2;;
		--ftpdir) ftpdir="$1"; shift 2;;
		--) shift ; break ;;
		*) log "Error parsing command line argument " $1 ; exit 1 ;;
	esac
done

if [ $# != "0" ] ; then
log "ABORTING. Found extraneous arguments $@"
exit 1
fi

log "Start of backup operations"

if [[ -z "$backupdir" ]] ; then 
    log "ABORTING. Backup directory not defined."
    exit 1
fi

#########################
# Backup mysql database #
#########################


if [ "$dbcompress" == "none" ] ; then
    compress_command="none"
    dbfile=$ARCHIVE_NAME-${timestamp}.sql
elif [ "$dbcompress" == "gzip" ] ; then
    compress_command="gzip"
    dbfile=$ARCHIVE_NAME-${timestamp}.sql.gz
elif [ "$dbcompress" == "bzip2"] ; then
    compress_command="bzip2"
    dbfile=$ARCHIVE_NAME-${timestamp}.sql.bz2
elif [ "$dbcompress" == "xz" ] ; then
    compress_command="xz"
    dbfile=$ARCHIVE_NAME-${timestamp}.sql.xz
fi

uploadfiles=( ${uploadfiles[@]} $dbfile )

    log "Dumping MySQL database"
if [[ $compress_command != "none" ]] ; then
    mysqldump --user=$dbuser --password=$dbpass $dbname | $compress_command > $backupdir/$dbfile  || log "Error dumping database"
else
    mysqldump --user=$dbuser --password=$dbpass $dbname > $backupdir/$dbfile || log "Error dumping database"
fi

####################
# Backup directory #
####################


dirfile=$ARCHIVE_NAME-${timestamp}.tar

for dir in "${sourcedirs[@]}" ; do 
    if [[ "$dry_run" == "yes" ]] ; then
	log "would append $dir to $dirfile"
    else
	log "Appending $dir to file archive"
	tar -r -f $backupdir/$dirfile $dir || log "Error appending $dir"
    fi
done

log "compressing file archive with $filecompress"
if  [[ "$filecompress" == "gzip" ]] ; then
    gzip $backupdir/$dirfile
    dirfile=${dirfile}.gz
elif [[ "$filecompress" == "bzip2" ]] ; then
    bzip2 $backupdir/$dirfile
    dirfile=${dirfile}.bz2
elif [[ "$filecompress" == "xz" ]] ; then
    xz $backupdir/$dirfile
    dirfile=${dirfile}.xz
fi

uploadfiles=( ${uploadfiles[@]} $dirfile )

###################
# Create checksum #
###################

if [[ "$checksum_algorithm" == "md5" ]] ; then
    checksumfile=$ARCHIVE_NAME-${timestamp}.md5
elif [[ "$checksum_algorithm" == "sha1" ]] ; then
    checksumfile=$ARCHIVE_NAME-${timestamp}.sha1
elif [[ "$checksum_algorithm" == "sha256" ]] ; then
    checksumfile=$ARCHIVE_NAME-${timestamp}.sha256
fi

# zero out checksumfile
echo -n > $backupdir/$checksumfile || log "Error zeroing out $backupdir/$checksumfile"

cd $backupdir
sumcmd=${checksum_algorithm}sum
for file in ${uploadfiles[@]} ; do
    ${sumcmd} $file >> $checksumfile || log "Error creating cecksum for $file"
done
cd -

uploadfiles=( ${uploadfiles[@]} $checksumfile )


################
# upload files #
################

if [[ "$keep_files" == "no" ]] ; then
    wput="wput --tries 1 --remove-source-files"
else
    wput="wput --tries 1"
fi

for file in ${uploadfiles[@]} ; do
    log "Uploading $file"
    $wput ${backupdir}/${file} ftp://${ftpusername}:${ftppassword}@${ftphost}/${ftpdir}/${file} || log "Error uploading $file"
done

log "End of backup operation"
