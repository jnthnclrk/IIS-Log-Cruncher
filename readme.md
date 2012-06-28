# IIS Log Cruncher
=================

IIS Log Cruncher is a Perl script developed to process large amounts of archived IIS log files on the command line. It was created so we could process years of log files with a few, relatively easy commands.

* process_arch.pl — the is the master script
	* flatten_zip.pl — extracts ZIP archives from ZIP/ RAR archives
recursively
	* filter_log.pl — extracts columns and filter rows from an input log file
	* filter_log.cfg — adjust various settings with this config file
* sanity_check.sh — a set of commands to check for verification

## Requirements

*  Unix platform, preferably Linux or Cygwin for Windows that includes:
    * Perl 5.8 or newer
    * Unzip v5.2 or newer (by Info-Zip); available as a package
under Cygwin and all Linux flavours
    * Unrar - http://www.cyberciti.biz/faq/unrar-apple-os-x-command-line-gui-tools/
    * "find" command
    * A decent command shell (e.g. "bash")

## Usage

### Simple

Processing a single daily archive…

    nice unzip -p input/dailyarchive.zip | nice perl filter_log.pl --config-file filter_log.cfg > output/dailyarchive.log 2> output/dailyarchive.msg

### Complex

Assuming that we have two subdirectories "input" and "output"
where "input" contains any number of ZIP archives, some containing
other ZIP archives.

First, flatten the archives...

    perl process_arch.pl --flatten ./input
    
Then clean it up a little...

    perl process_arch.pl --cleanup ./input
    
Then start the process as a dry run...
    
    perl process_arch.pl --filter-log --dry-run
    
Start the process for real...

    perl process_arch.pl --filter-log
    
## Error checking
    
### Simple sanity checks

Count lines in mutiple log files in a directory…

    wc -l filename*
    
Count lines in a single daily ZIP archive

    unzip -p dailyarchive.zip  |  wc -l

Search for lines containing a string in a ZIP archive...

    unzip -p dailyarchive.zip | egrep 'SEARCHSTRING' | wc -l

Search for lines not containing a string in a ZIP archive...

    unzip -p dailyarchive.zip | egrep -v 'SEARCHSTRING' | wc -l
    
Search for lines containing a string in a BZ2 archive

    bzcat dailyarchive.bz2 | egrep 'SEARCHSTRING' | wc -l
    


Sample the header info...
    
    unzip -p logfile.zip | egrep -i  '^Fields:' | sed 's/^.*#//p' | sort -u
    
### Advanced sanity checks

There also a shell script for further, more detailed sanity checks. This script runs a number of tests and if it finds problems it will print out source line numbers that have issues. Note: this script may run slowly.

    ./sanity_checks.sh
    
If I certain line number is problematic you can use the following command to find the line in the source archive. Note: this command may run very slowly.

    unzip -p dailyarchive.zip | egrep -n '.*'  | egrep '^(LINENUM1|LINENUM2):'

## Performance

On a 2009 MacBook Pro we were able to process around 70,000 lines per second.