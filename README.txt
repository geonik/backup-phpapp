This a simple script to backup an PHP application to a web server.

Such an application typically consists of a MySQL database and a directory under
which all application files reside.

If your application fits the above description this script will fit you nicely.

After taking the backup the application pushes (using wput) the files to an ftp
server for remote backing up. After that local files are deleted. You can keep
the local files with the --keep-files option.

