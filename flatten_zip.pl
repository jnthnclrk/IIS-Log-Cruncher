#!/usr/bin/perl
#
# FLATTEN_ZIP.PL:
#
# Quick script to recursively extract ZIP files from ZIP archives
# under a given base directory.  If a file x/y/z.zip contains zip
# archives, they will be expanded under the subdirectory
# x/y/__z.  The files so extracted will, in turn, be examined.  No
# file is examined twice in run.
#
# Sample usage in a Unix command shell:
#
# 	perl flatten_zip.pl input_data
#
# Requirements:		Perl 5.8 or higher preferably in a Unix shell
#					Info-Zip unzip v5.2 or higher (must support
#						-d and -p switches)
#					Basic Unix "find" command.
#
# Notes:			The file/directory path analysis is not
#					bulletproof.  Path elements that contain
#					escaped or embedded slashes (extremely rare)
#					will break it.

use Getopt::Long;

my $opt_help;

my $opt_result = GetOptions(
					"help" => \$opt_help,
					);
					
if ( ! $opt_result || $opt_help ) {
	die "Use:  $0 [--help] [base_directory]\n";
}

my $FIND = '/usr/bin/find';
my $UNZIP = '/usr/bin/unzip';

my @queue = ();
my %seen = ();
my @base_dirs = ();

foreach my $dir ( @ARGV ) {
	print STDERR "--> DIR = $dir\n";
	next unless -d $dir;
	push @base_dirs, $dir;
}

# If no directories specified, use the current one.

unless ( scalar @base_dirs ) {
	push @base_dirs, '.';
}

# Populate the queue of zip files.

my $base_dirs_string = "'" . join("' '", @base_dirs) . "'";
print STDERR "--> BASE DIRS:  $base_dirs_string\n";
@queue = split(/[\r\n]+/, `$FIND $base_dirs_string -type f -name '*.zip' -print`);

while ( my $zip_file = shift @queue ) {
	next unless $zip_file =~ /^(.*\/)(.*)(\.zip)$/;
	next if $seen{$zip_file};
	
	print STDERR "---> Processing $zip_file\n";
	
	my ( $dir, $stub, $zip ) = ( $1, $2, $3);
	my $tmp_dir = $dir . '__' . $stub;
	system("$UNZIP -d '$tmp_dir' '$zip_file' \\*.zip");
	my @new_files = split(/[\r\n]+/, `$FIND '$tmp_dir' -type f -name '*.zip' -print`);
	
	if ( scalar @new_files ) {
		print STDERR "-----> Queueing ", join(', ', @new_files), "\n";
		unshift @queue, @new_files;
	} else {
		print STDERR "-----> No zip files in archive.\n";
		rmdir($tmp_dir);
	}
	
	$seen{$zip_file} += 1;
}

