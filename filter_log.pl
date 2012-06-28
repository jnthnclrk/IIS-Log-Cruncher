#!/usr/bin/perl
#
# FILTER_LOG.PL:
#
# Simple script to be used as a filter to extract the desired fields of an IIS log
# passed through the standard input stream and dump them into the output stream.
#
# Sample usage in a Unix command shell:
#
# 	unzip -p logfiles_YYYYMMDD.zip \*.log  \
#		| perl filter_log.pl --verbose \
#			--config-file=filter_log.cfg \
#		| bzip2 -c > logfiles_YYYYMMDD.log.bz2
#		
# Requirements:		Perl 5.8 or later, preferably on a Unix platform

use Data::Dumper;

my $DEBUG = 0;

# Default options.

my $opts = new MyParams( {
				verbose => 1,
				'output-fields' => 'iso_date,iso_time,http_server_ip,http_client_referer',
				'start-date' => '1969-01-01',
				'end-date' => '2036-12-31',
				'output-separator' => ' '
			} );
			
# Options from command line.

my $opt_result = $opts->load_getopts();

if ( ! $opt_result  || ( exists($opts->{'help'}) && $opts->{'help'} ) ) {
	die "Use:  $0\n",
		"\t\t[--verbose] [--count-rows] [--help]\n",
		"\t\t[--start-date=YYYY-MM-DD] [--end-date=YYYY-MM-DD]\n",
		"\t\t[--config-file=path_of_config_file]\n",
		"\t\t[--print-line-numbers]\n";
}

# Options from configuration file only if --config-file=file specified 
# on command line.

if ( exists($opts->{'config-file'}) && $opts->{'config-file'} ) {
	$opts->load_config_file();
}

# Import options as variables $opt_verbose, $opt_output_fields, etc., into
# the current context.
#
# Note that some of these will be scalars and some will be hash or array refs.

my $import_options = $opts->import_options();
eval $import_options;
die "$0:  Error importing options variables ($@).\n" if $@;

# Instantiate log filter and load options.

my $log_filter = new MyLiteLogFilter( {
						'verbose' => $opt_verbose,
						'start-date' => $opt_start_date,
						'end-date' => $opt_end_date,
						'output-separator' => $opt_output_separator,
						'output-fields' => $opt_output_fields,
						'count-rows' => $opt_count_rows,
						'keep-if' => $opt_keep_if
				} );
						
my $stats = {
	start_time => time(),				# Record start time.
	warnings => {
		bad_input_records => 0			# Counter for bad input records
		}
};

# Input stream is processed one line at a time.  We assume that multiple log files
# may be concatenated in the same stream.  When this occurs, attention must be
# paid to any input structure directives (MSIIS logs, in particular) contained
# in comments.

my $buff;

while ( $buff = <STDIN> ) {
	$stats->{lines}->{total} += 1;
	next if $buff =~ /^\s*$/s;			# Skip empty lines
	
	# Parse comment blocks for clues (IIS logs)
	
	if ( $buff =~ /^\s*#/ ) {
		$comment_block .= $buff;
		next;
	}
	
	# First non-blank, non-comment line is end-of-block
	
	if ( $comment_block ) {
		$stats->{comment_blocks}->{total} += 1;
		
		# Parse the accumulated block for structure information
		
		unless ( $log_filter->parse_comment_block( $comment_block ) ) {
			die "$0:  Unable to parse comment block ($comment_block).\n";
		}
	
		$comment_block = undef;
		$in_fields = $log_filter->{in_fields};
		$canon_fields_mapped_to_input = $log_filter->{canon_fields_mapped_to_input};
		
		$opt_verbose &&
			print STDERR "\n\nNew input file starting at line ", $stats->{lines}->{total}, ":\n\t",
				join("\n\t",
					"Date / time:\t" .
						$log_filter->{date_time}->{day} . ' ' .
						$log_filter->{date_time}->{'time'},
					"Input fields:\t" .
						join(', ', @$in_fields),
					"Mapped fields:\t" .
						join(', ', @$canon_fields_mapped_to_input),
					"Block:\t" . $log_filter->{in_block}
					), "\n\n";
		
		# Create and load in-line script to process the input stream
		# until the next comment line.  This method will use the 
		# information compiled from the last call to parse_comment_block().
		
		my $filter_script = $log_filter->import_script();
		
		$opt_verbose &&
			print STDERR "\n\nFilter script:\n\n$filter_script\n\n";
		
		# Back up the line counter by 1.  The first line here gets
		# counted twice otherwise.
		
		$stats->{lines}->{total} -= 1;
		
		# Attempt to run the script in a sub-block.  BTW, this is the
		# only way we'll know if the regexes for the keep-if filters are
		# valid.
		
		eval $filter_script;
		die "$0:  Error executing filter script ($@).\n" if $@;
		
		# Line count adjustment.  First comment line after the embedded
		# script is not counted.
		
		$stats->{lines}->{total} += 1;
		next;
	}
		
	# We shouldn't actually get here.
	
	die "$0:  Cannot process input ($buff).\n";
}

# Dump some stats.

$opt_verbose && 
	print STDERR "\nStatistics:\n",
		join("\n\t",
			"Elapsed Time (s):\t" . ( time() - $stats->{start_time} ),
			"Input lines processed:\t" . $stats->{lines}->{total},
			"Comment headers:\t" . $stats->{comment_blocks}->{total},
			"Data rows processed:\t" . $stats->{lines}->{data},
			"Invalid data rows skipped:\t" . $stats->{warnings}->{bad_input_records},
			"Filtered rows kept:\t" . $stats->{lines}->{kept}
			), "\n\n";
	
exit 0;


# PACKAGE MyParams:		Default, command line, config file params
#						processing.

package MyParams;

use Data::Dumper;
use Getopt::Long;

# Parameter import handlers.

our $__opt_tbl;

sub __import_boolean {
	my $self = shift;
	my $key = shift;
	my $val = shift;
	
	$self->{$key} = ( $val ? 1 : 0 );
	return 1;
}

# Really loose interpretation of an ISO date format.

sub __import_iso_date {
	my $self = shift;
	my $key = shift;
	my $val = shift;
	
	die "$0:  Invalid ISO date ($key = \"$val\").\n"
		unless $val =~ /(\d\d\d\d)\D*(\d\d)\D*(\d\d)/;
		
	my ( $yyyy, $mm, $dd ) = ( $1, $2, $3 );
	
	die "$0:  Invalid ISO date ($key = \"$val\").\n"
		unless (
			$yyyy ge '1969' and $yyyy le '2036' and
			$mm ge '01' and $mm le '12' and
			$dd ge '01' and $dd le '31'
		);
		
	$self->{$key} = join('-', $1, $2, $3);
}
		
sub __import_nonempty {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	die "$0:  Invalid non empty value ($key = \"$val\").\n"
		if $val eq '';
		
	$self->{$key} = $val;
}

sub __import_array {
	my $self = shift;
	my $key = shift;
	my $val = shift;
	
	my @list = split(/,/, $val);
	
	die "$0:  Missing list ($key = \"$val\").\n"
		unless scalar @list;
		
	$self->{$key} = \@list;
}

sub __import_keep_rule {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	push(@{$self->{$key}}, ref($val) eq 'ARRAY' ? @$val : $val);
}

sub __import_config_file {
	my $self = shift;
	my $key = shift;
	my $val = shift;
	
	die "$0:  Missing or invalid configuration file ($key = \"$val\").\n"
		unless ( -f $val and -r $val );
		
	$self->{$key} = $val;
}

# Allowable command line / config file options.  Add new ones to this list
# and be prepared to correctly determine the 'getopts' processor string
# and code the handler function (called by the load() method).

sub __init {
	$__opt_tbl = {
		'verbose' => {
			handler => \&__import_boolean,
			'getopts' => ''
			},
		'help' => {
			handler => \&__import_boolean,
			'getopts' => ''
			},
		'start-date' => {
			handler => \&__import_iso_date,
			'getopts' => '=s'
			},
		'end-date' => {
			handler => \&__import_iso_date,
			'getopts' => '=s'
			},
		'output-separator' => {
			handler => \&__import_nonempty,
			'getopts' => '=s'
			},
		'output-fields' => {
			handler => \&__import_array,
			'getopts' => '=s'
			},
		'count-rows' => {
			handler => \&__import_boolean,
			'getopts' => ''
			},
		'keep-if' => {
			handler => \&__import_keep_rule,
			'getopts' => '=s@'
			},
		'config-file' => {
			handler => \&__import_config_file,
			'getopts' => '=s'
			},
		'print-line-numbers' => {
			handler => \&__import_boolean,
			'getopts' => ''
			}
		};
}

# Constructor.  Includes optional loading of defaults.

sub new {
	my $class = shift;
	my $defaults = shift;
	my $self = {};
	bless $self, $class;
	
	__init() unless $__opt_tbl;
	
	die "$0:  Parameter defaults must be a hash.\n"
		unless ref($defaults) eq 'HASH';
		
	$self->load($defaults);
	return $self;
}

# Load from an input hash.  Input hash may come from multiple
# sources.

sub load {
	my $self = shift;
	my $input_params = shift;
	
	die "$0:  MyParams->load:  Parameter inputs must be a hash ref.\n"
		unless ref($input_params) eq 'HASH';
	
	$DEBUG && print STDERR "----> INPUT_PARAMS:  ", Dumper($input_params), "\n\n";
	
	while ( my ( $key, $val ) =  each %$input_params ) {
		die "$0:  Invalid command parameter:  $key.\n"
			unless ( exists($__opt_tbl->{$key}) );
		my $handler = $__opt_tbl->{$key}->{'handler'};
		&$handler($self, $key, $val);
	}
	
	return;
}
	
# Load from GetOpt::Long.  Parameter names are taken from
# %$__opt_tbl hash.

sub load_getopts {
	my $self = shift;
	
	my $opts = {};
	my @list;
	
	while ( my ( $key, $val ) = each %$__opt_tbl ) {
		next unless exists($val->{getopts});
		push(@list, $key . $val->{getopts});
	}
	
	my $result = GetOptions($opts, @list);
	$self->load($opts);
	return $result;
}


# Load from simple configuration file.  Structure is more less like this:
#
#	# Comment
#
#	attribute1 = value1
#	attribute2 = value2
#		value3
#		value4
#	attribute3 = value5

sub load_config_file {
	my $self = shift;

	# No configuration file defined.
	
	unless ( exists($self->{'config-file'}) ) {
		warn "$0:  No configuration file defined.  Skipping.\n";
		return;
	}
	
	my $config_file = $self->{'config-file'};
	my $fh;
	
	open($fh, '<', $config_file) ||
		die "$0:  Unable to open configuration file (",
			$config_file. ").\n";
			
	my $key;
	my $val;
	
	# Pull key = value pairs from configuration file.  Neither
	# keys nor values span line breaks.  Keys cannot contain
	# white space but they can contain hyphens.
	
	while ( my $line = <$fh> ) {
		$line =~ s/^\s*//s;
		$line =~ s/\s*$//s;
		next unless $line;
		next if $line =~ /^[#;]/;
		
		if ( $line =~ /^([a-z][a-z0-9_-]*)\s+[=:]\s+(\S.*)$/si ) {
			( $key, $val ) = ( $1, $2 );
		} elsif ( $line =~ /^([a-z][a-z0-9_-]*)\s+[=:]$/i ) {
			$key = $1;
			$val = undef;
		} elsif ( $line =~ /^(\S.*)$/ ) {
			$val = $1;
		} else {
			die "$0:  Invalid line ($line) in configuration file ($config_file).\n";
		}
		
		next unless $val;
		
		# Rudimentary removal of enclosing quotes around value.
		# Pass key / value pair to loader for further parsing.
		
		$val =~ s/^['"]//;
		$val =~ s/['"]$//;
		$self->load( { $key => $val } );
	}
			
	close($fh);
	return;
}
	
# When called, the resulting script should be eval'd in the current context
# (i.e. not in its own block).
#
# e.g.	my $opt_script = $opts->script('$opts') || die "...";
#		eval $opt_script;
#		die "$0:  Error loading options ($@).\n" if $@;

sub import_options {

	my $self = shift;
	my $output_var_prefix = shift || '$opt_';
	my @script = ();
		
	foreach my $key ( sort keys %$__opt_tbl ) {
		my $opt_var_name = $output_var_prefix . $key;
		$opt_var_name =~ s/-/_/g;
		
		if ( exists($self->{$key}) ) {
			my $val = $self->{$key};
			$Data::Dumper::Terse = 1;
			push(@script, "$opt_var_name = " . Dumper($val) . ";");
			$Data::Dumper::Terse = undef;
		}
	}
	
	return join("\n", @script);
}
	
	
# MyLiteLogFilter:
#
# Package for constructing a lightweight filter for an open [MS IIS] 
# HTTP log stream.

package MyLiteLogFilter;

use Data::Dumper;

our @__output_canon_fields;
our %__output_canon_fields_by_name;
our %__map_to_canon_name;
our @__logfilter_params;
our %__logfilter_params_by_name;

sub __init {

	# Acceptable universal log fields that can be used in the definition
	# of filters or output column sets.  Avoid names that are significant
	# to Perl as built-in functions or symbols.
	#
	# Add names as needed.

	@__output_canon_fields = (
		'iso_date',
		'iso_time',
		'http_server_ip',
		'http_method',
		'http_uri',
		'http_query',
		'http_server_port',
		'http_client_user',
		'http_client_ip',
		'http_client_user_agent',
		'http_client_referer',
		'http_response_status',
		'http_response_substatus',
		'http_response_win32_status',
		'http_response_size'
	);					
		
	# Lookup for accepted canonical fields.

	@__output_canon_fields_by_name{@__output_canon_fields} = ( 1 ) x 
		scalar @__output_canon_fields;
		
	# Mapping of known MSIIS column names to canonical log file column names.
	# Add new mappings to this hash definition.

	%__map_to_canon_name = (
		'date' => 'iso_date',
		'time' => 'iso_time',
		's-ip' => 'http_server_ip',
		'cs-method' =>  'http_method',
		'cs-uri-stem'  => 'http_uri',
		'cs-uri-query'  => 'http_query',
		's-port'  => 'http_server_port',
		'cs-username' =>  'http_client_user',
		'c-ip'  => 'http_client_ip',
		'cs(User-Agent)' =>  'http_client_user_agent',
		'cs(Referer)' =>  'http_client_referer' ,
		'sc-status' =>  'http_response_status'  ,
		'sc-substatus' =>  'http_response_substatus'  ,
		'sc-win32-status' =>  'http_response_win32_status' 	,
		'sc-bytes' =>  'http_response_size'  
	);												

	# Acceptable parameters that can be loaded.  If you add new
	# parameters to this list you must write the loader block in the
	# load() method.

	@__logfilter_params = (
		'verbose',
		'start-date',
		'end-date',
		'output-separator',
		'output-fields',
		'count-rows',
		'keep-if',
		'print-line-numbers'
	);

	@__logfilter_params_by_name{@__logfilter_params} = ( 1 ) x scalar
			@__logfilter_params;
}

# Constructor.

sub new {
	my $class = shift;
	my $defaults = shift;
	
	my $self = {
		in_fields => [],
		in_separator => ' ',
		canon_fields_mapped_to_input => [],		# Ordered list of mapped output fields
		keep_if_rules => []
	};
	
	bless $self, $class;
	
	die "$0:  Parameter defaults must be a hash.\n"
		unless ref($defaults) eq 'HASH';
	
	__init() unless @__logfilter_params;
	
	$self->load($defaults);
	return $self;
}

# Load and parse parameters.

sub load {
	my $self = shift;
	my $input_params = shift;
	
	die "$0:  Parameter inputs must be a hash reference.\n"
		unless ref($input_params) eq 'HASH';	
	
	while ( my ( $key, $val ) =  each %$input_params ) {
	
		$DEBUG && print STDERR "---> MyLiteLogFilter->load:  KEY=$key;  VAL=$val\n";
		
		die "$0:  Invalid command parameter:  $key = \'$val\'.\n"
			unless ( exists($__logfilter_params_by_name{$key}) );
		
		unless ( defined($val) ) {
			warn "$0:  Option (name=\"$key\") was passed but no value was supplied.  Skipping.\n";
			next;
		}
			
		if ( $key =~ /(verbose|count-rows|date|output-separator|print-line-numbers)/ ) {
			$self->{$key} = $val;
			
		# Output fields are not cumulative on each call to load().
		
		} elsif ( $key eq 'output-fields' ) {
			die "$0:  Output fields must be in an array ref.\n"
				unless ref($val) eq 'ARRAY';
			$self->{output_canon_fields} = [];
			
			foreach my $output_field_name ( @$val ) {
				die "$0:  Invalid output field name ($output_field_name).\n"
					unless exists($__output_canon_fields_by_name{$output_field_name});
				push(@{$self->{output_canon_fields}}, $output_field_name);
			}
			
		# Keep-if rules are cumulative.
		
		} elsif ( $key eq 'keep-if' ) {
			die "$0:  Keep-if rules must be in an array ref.\n"
				unless ref($val) eq 'ARRAY';
			
			foreach my $rule ( @$val ) {
			
				# Rules have the form:  CANON_COLUMN OP VALUE
				
				die "$0:  Invalid keep-if rule ($val).  Should be VAR OP VALUE\n"
					unless ( $rule =~ /
								([a-z][_a-z0-9]*)\s+
								([=!]~|<=?|>=?|[gl][et]|eq|ne|==)\s+
								(\S.*)
								/ix
							);
				
				my ( $varname, $op, $rhs ) = ( lc($1), lc($2), $3 );
				
				# Test varname
				
				die "$0:  Bad variable name in keep-if rule ($val).\n"
					unless exists($__output_canon_fields_by_name{$varname});
					
				# Massage right hand side to agree with operation. 
				
				if ( $op =~ /~/ ) {
					my $re_opt = '';
					
					if ( $rhs =~ /^\/(.*)\/(i?)$/ ) {
						$rhs = $1;
						$re_opt = $2 || '';
					} elsif ( $rhs =~ /\// ) {
						$rhs =~ s/\//\\\//g;
					}
					
					$rhs = '/' . $rhs . '/' . $ re_opt;
				} elsif ( $op =~ /([gl][et]|eq|ne)/ ) {
					if ( $rhs =~ /^['"](.*)['"]$/ ) {
						$rhs = $2;
					}
					
					$rhs = "'" . $rhs . "'";
				} else {
					die "$0:  Righthand side must be a number ($val).\n"
						unless ( $rhs =~ /^[+-]?\d+(:?\.\d*)?$/ );
				}
				
				# Push the filter expression into the stack.
				
				push(@{$self->{keep_if_rules}}, '$' . $varname . ' ' . $op . ' ' .
					$rhs);
			}
		}
	}			

	return;
}

# Reads a structured block harvested from the input stream and attempts
# to use it to decipher following data rows.

sub parse_comment_block {

	my $self = shift;
	my $block = shift;
	
	# Add other block regex's as if/elseif blocks.  Each if/elseif block
	# populates a structure describing an input line.  This method is more
	# or less biased towards matching MS IIS logs.
	
	if ( $block =~ /
			\#Software:\s+(Microsoft.*\S)\s+
			\#Version:\s+(\S+)\s+
			\#Date:\s+(\d\d\d\d-\d\d-\d\d)\s+(\d\d:\d\d:\d\d)\s+
			\#Fields:\s+(\S.*\S)
			/xsi
		) {
		my $server = {
				name => $1,
				version => $2
				};
		my $date_time = {
				day => $3,
				'time' => $4
				};
		
		# Load the MS IIS log semantics (input field names and order).
		
		my $in_fields_str = $5;
		my @in_fields = split(/\s+/, $in_fields_str);
		my @canon_fields_mapped_to_input;
		
		# Build list canonical column names matching input fields.
		
		foreach my $fld ( @in_fields ) {
			my $canon_name = 'http_unknown';
			
			if ( exists($__map_to_canon_name{$fld}) ) {
				$canon_name = $__map_to_canon_name{$fld};
			} else {	
				warn "$0:  Unknown (unmapped) MS IIS field ($fld) will be ignored.\n";
			}
			
			push(@canon_fields_mapped_to_input, $canon_name);
		}
			
		# Store parsed info into object.
		
		$self->{in_fields} = \@in_fields;
		$self->{canon_fields_mapped_to_input} = \@canon_fields_mapped_to_input;
		$self->{in_block} = $block;
		$self->{server} = $server;
		$self->{date_time} = $date_time;
		
		return 1;
		}
	
	# If no matches, return 0.
	
	return 0;
}

# Build and dump script to be embedded in stream processing loop.
# Must be preceded by call to method parse_comment_block().

sub import_script {

	my $self = shift;
	my $input_stream_handle_varname = shift || 'STDIN';
	my $output_stream_handle_varname = shift || 'STDOUT';
	my $input_buff_varname = shift || '$buff';
	my $comment_block_varname = shift || '$comment_block';
	my $opt_varname_prefix = shift || '$opt_';
	my $stats_varname = shift || '$stats';
	
	my @input_canon_flds = @{$self->{canon_fields_mapped_to_input}};
	grep(!s/^/\$/, @input_canon_flds);
	my $input_canon_fld_vars_as_string = join(', ', @input_canon_flds);
			
	die "$0:  Missing mapped canonical fields.\n"
		unless $input_canon_fld_vars_as_string;
	
	# Start and end-date conditions are just keep-if filters.
	
	my @filters = (
		"\$iso_date ge ${opt_varname_prefix}start_date",
		"\$iso_date le ${opt_varname_prefix}end_date"
	);
	
	push(@filters, @{$self->{keep_if_rules}});
	my $filters_as_string = join(" && ", @filters);
	my $input_separator = $self->{in_separator};
	my @output_canon_flds = @{$self->{output_canon_fields}};
	my $output_canon_fld_names_as_string = join($self->{'output-separator'}, @output_canon_flds);
	grep(!s/^/\$/, @output_canon_flds);
	my $output_canon_fld_vars_as_string = join(', ', @output_canon_flds );
	
	my $script_template = <<EOB;
		#
		# FILTER SCRIPT
		#
		
		${opt_varname_prefix}verbose &&
			print STDERR "---> opt_start_date = ${opt_varname_prefix}start_date\\n";
			
		print $output_stream_handle_varname "#Fields:  $output_canon_fld_names_as_string\\n";
		
		my ( $input_canon_fld_vars_as_string );
		my \@expected_input_fields = ( $input_canon_fld_vars_as_string );
		my \$num_expected_input_fields = scalar \@expected_input_fields;
		my \@current_input_fields;
		my \$num_current_input_fields;
		
		while ( $input_buff_varname !~ /^\\s*#/ ) {
			${stats_varname}->{lines}->{total} += 1;
			
			unless ( $input_buff_varname =~ /^\\s*\$/s ) {
				${stats_varname}->{lines}->{data} += 1;
				
				${opt_varname_prefix}verbose && ${opt_varname_prefix}count_rows &&
					${stats_varname}->{lines}->{data} % 1000 == 0 &&
						printf STDERR "---> Data row %10d\\r", ${stats_varname}->{lines}->{data};
						
				\@current_input_fields = ( $input_canon_fld_vars_as_string ) = split('$input_separator', $input_buff_varname);
				\$num_current_input_fields = scalar \@current_input_fields;
				
				if ( \$num_current_input_fields != \$num_expected_input_fields ) {
					warn "$0:  Wrong number of fields (", \$num_current_input_fields, 
						") in input row (line #", ${stats_varname}->{lines}->{total}, ").  \n",
						"Skipping... FLDS = (", join(', ', \@current_input_fields), ").\n";
					${stats_varname}->{warnings}->{bad_input_records} += 1;
				 } elsif ( $filters_as_string ) {
					${stats_varname}->{lines}->{kept} += 1;
					${opt_varname_prefix}print_line_numbers && 
						print $output_stream_handle_varname ${stats_varname}->{lines}->{total}, ':';
					print $output_stream_handle_varname 
						join("${opt_varname_prefix}output_separator", $output_canon_fld_vars_as_string), "\\n";
				}
			}
			
			last unless ( $input_buff_varname = <$input_stream_handle_varname> );
			
			if ( $input_buff_varname =~ /^\\s*#/ ) {
				$comment_block_varname = $input_buff_varname;
			}
		}		
EOB
	
	return $script_template;
}