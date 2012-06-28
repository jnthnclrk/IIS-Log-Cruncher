#!/usr/bin/perl
#
# PROCESS_ARCH.PL:
#
# Quick script to recursively process ZIP/RAR files from ZIP/RAR archives
# under a given base directory.  If a file x/y/z.zip contains zip
# archives, they will be expanded under the subdirectory
# x/y/__z.  The files so extracted will, in turn, be examined.  No
# file is examined twice in run.
#
# Sample usage in a Unix command shell:
#
# 	perl process_arch.pl --flatten  input_dir
#	perl process_arch.pl --cleanup  input_dir
#	perl process-arch.pl --filter-log input_dir
#
# Requirements:		Perl 5.8 or higher preferably in a Unix shell
#					Info-Zip unzip v5.2 or higher (must support
#						-d and -p switches)
#					Basic Unix "find" command.
#					Unrar 3.93 or higher (must support "p" command
#						(print to STDOUT) and "-inul" option (terse))
#
# Notes:			The file/directory path analysis is not
#					bulletproof.  Path elements that contain
#					escaped or embedded slashes (extremely rare)
#					will break it.

use Getopt::Long;

my $opt_help;
my $opt_cleanup;
my $opt_filter_log;
my $opt_output_root = 'output';
my $opt_dry_run;
my $opt_flatten;

my $opt_result = GetOptions(
					"help" => \$opt_help,
					"cleanup" => \$opt_cleanup,
					"filter-log" => \$opt_filter_log,
					"output-root=s" => \$opt_output_root,
					"dry-run" => \$opt_dry_run,
					"flatten" => \$opt_flatten
					);
					
if ( ! $opt_result || $opt_help ) {
	die "Use:  $0\t[--help] [--cleanup] [--filter-log [--dry-run]]\n\t\t\t[--flatten] [--output-root=OUTPUT_ROOT] [base_directory]\n";
}

my $FIND = 'find';
my $UNZIP = 'unzip';
my $UNRAR = 'unrar';
my $RM = 'rm';
my $BZIP2 = 'bzip2';
my $MKDIR = 'mkdir -p';

my $FILTER_LOG_SCRIPT = 'filter_log.pl';
my $FILTER_LOG_CFG = 'filter_log.cfg';

# All temporary subdirectory names created by this script will be prefixed with
# $TMP_DIR_PREFIX.

my $TMP_DIR_PREFIX = '__fz__';

my @queue = ();
my %seen = ();
my @base_dirs = ();

foreach my $dir ( @ARGV ) {
	print STDERR "--> DIR = $dir\n";
	next unless -d $dir;
	push @base_dirs, $dir;
}

# If no directories specified, use the "input" subdirectory of the current one.

unless ( scalar @base_dirs ) {
	push @base_dirs, 'input';
}

# Cleanup directories with the prefix $TMP_DIR_PREFIX

if ( $opt_cleanup ) {
	print STDERR "--> Cleaning up temp directories and contents (prefix=$TMP_DIR_PREFIX)...\n";
	@queue = split(/[\r\n]+/, `$FIND $base_dirs_string -depth -type d -name '${TMP_DIR_PREFIX}*' -print`);
	
	foreach my $dir ( @queue) {
		print STDERR "---> Removing $dir and contents.\n";
		system("$RM -r -f $dir") == 0 ||
			die "$0:  Error removing directory ($!).\n";
	}
	
	exit 0;
}

# Execute this script as a wrapper for filter_log.pl

if ( $opt_filter_log ) {
	die "$0:  Filter log script does not exist ($FILTER_LOG_SCRIPT).\n"
		unless -f $FILTER_LOG_SCRIPT;
	die "$0:  Filter log config file does not exist ($FILTER_LOG_CFG).\n"
		unless -f $FILTER_LOG_CFG;
		
	use Cwd 'abs_path';
	my $filter_log_script = abs_path($FILTER_LOG_SCRIPT);
	my $filter_log_cfg = abs_path($FILTER_LOG_CFG);
	my $output_root = abs_path($opt_output_root);
	
	my $input_dir = shift(@base_dirs) ||
		die "$0:  A single input root directory is needed for this operation.\n";
		
	chdir($input_dir) ||
		die "$0:  Cannot chdir to $input_dir.  Check permissions and existence.\n";
		
	print STDERR "\n--> Wrapping \"$FILTER_LOG_SCRIPT\" script for processing $input_dir -> $opt_output_root.\n\n";
	@queue = split(/[\r\n]+/, `$FIND . -type f \\( -iname '*.zip' -o -iname '*.rar' \\) -print`);
	
	foreach my $arch_file ( @queue ) {
		next unless $arch_file =~ /^(.*)\/(.*)\.(zip|rar)$/;
		my ( $dir, $stub, $type ) = ( $1, $2, $3);
		$dir =~ s/^\.\/?//;
		my $output_dir = $output_root . ( $dir ? ('/' . $dir ) : '');
		my $output_file = $output_dir . '/' . $stub . '.log.bz2';
		my $output_msg = $output_dir . '/' . $stub . '.msg';
		
		print STDERR "\nExecuting script \"$filter_log_script\" on \"$arch_file\" -> \"$output_file\".\n";
		
		my $pipe_head = "nice $UNZIP -p $arch_file \\*.log";
		
		if ( $type eq 'rar' ) {
			$pipe_head = "nice $UNRAR p -inul $arch_file \\*.log";
		}
		
		my $mkdir = "$MKDIR $output_dir";
		print STDERR "----> MKDIR = $mkdir\n";
		
		unless ( $opt_dry_run && ! -d $output_dir ) {
			system($mkdir) == 0 ||
				die "$0:  Error creating directory $output_dir ($!).\n";
		}
		
		my $cmd = "$pipe_head | nice perl $filter_log_script --config-file $filter_log_cfg 2>$output_msg | nice $BZIP2 -c >$output_file";
		print STDERR "----> FILTER_LOG_PIPELINE = $cmd\n";
		
		unless ( $opt_dry_run ) {
			system($cmd) == 0 ||
				die "$0:  Error processing \"$arch_file\" -> \"$output_file\"\n";
		}
	}
	
	exit 0;
}
			
# Populate the queue of zip / rar files.

if ( $opt_flatten ) {
	my $base_dirs_string = "'" . join("' '", @base_dirs) . "'";
	print STDERR "--> BASE DIRS:  $base_dirs_string\n";
	@queue = split(/[\r\n]+/, `$FIND $base_dirs_string -type f \\( -iname '*.zip' -o -iname '*.rar' \\) -print`);

	while ( my $arch_file = shift @queue ) {
		next unless $arch_file =~ /^(.*\/)(.*)\.(zip|rar)$/;
		next if $seen{$arch_file};
		
		print STDERR "\n---> Processing archive:  $arch_file\n";
		
		my ( $dir, $stub, $type ) = ( $1, $2, $3);
		my $tmp_dir = $dir . $TMP_DIR_PREFIX . $stub;
		
		if ( $type eq 'zip' ) {
			system("$UNZIP -d '$tmp_dir' '$arch_file' \\*.zip \\*.rar");
		} elsif ( $type eq 'rar' ) {
			system("mkdir '$tmp_dir' && cd '$tmp_dir' && $UNRAR e '../${stub}.${type}' \\*.zip \\*.rar");
		} else {
			die "$0:  Unknown file type ($type) for file $arch_file.\n";
		}
		
		my @new_files = split(/[\r\n]+/, `$FIND '$tmp_dir'  -type f \\( -iname '*.zip' -o -iname '.*.rar' \\) -print`);
		
		if ( scalar @new_files ) {
			print STDERR "-----> Queueing ", join(', ', @new_files), "\n";
			unshift @queue, @new_files;
		} else {
			print STDERR "-----> No zip or rar files in archive.\n";
			rmdir($tmp_dir);
		}
		
		$seen{$arch_file} += 1;
	}

	exit 0;
}
