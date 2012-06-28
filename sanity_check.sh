#!/bin/bash

#
# FILTER_LOG.PL:	BUILD STUDY FILE - line numbers of records in original log
#					file that match the filter(s), one per output line.
#

#	Raw output file (log extraction, rewriting...  output prefixed by
#	original line numbers):

echo 'Running FILTER_LOG.PL...'
unzip -p input/__fz__ex1202/ex120202.zip | \
	perl filter_log.pl --print-line-numbers --config-file filter_log.cfg 2> errors/ex120202/ex120202.msg | \
	bzip2 -c > errors/ex120202/ex120202.log.bz2
	
echo 'Number of raw output records minus inserted comments:'
bzcat errors/ex120202/ex120202.log.bz2 | egrep -v '^#Fields:' | wc -l

echo 'Building study file (extracting source row numbers...'
bzcat errors/ex120202/ex120202.log.bz2 | egrep -v '^#Fields:' | awk -F: '{print $1}' > errors/ex120202/extract_matches_filter-log.txt

#
# EGREP:	BUILD STUDY FILE - line numbers of records in original log
#			file that match the filter(s), one per output line.
#

# Raw output file (log extraction... output prefixed by
#	original line numbers):

echo 'Running EGREP...'
unzip -p input/__fz__ex1202/ex120202.zip | \
	egrep -i -v -n ' https?://[^ /]*mydomain\.com[^ ]*' | \
	bzip2 -c > errors/ex120202/ex120202.log.bz2
	
echo 'Number of raw output records minus IIS comments:'
bzcat errors/ex120202/ex120202.log.bz2 | egrep -v '^[0-9]+:#' | wc -l

echo 'Building study file (extracting source row numbers...'
bzcat errors/ex120202/ex120202.log.bz2 | egrep -v '^[0-9]+:#' | awk -F: '{print $1}' > errors/ex120202/extract_matches_egrep.txt

echo 'Comparing study files... (diff).  No output indicates perfect match.'
diff errors/ex120202/extract_matches_filter-log.txt errors/ex120202/extract_matches_egrep.txt
echo '...Done'
