package kronekeeper::Frame::Import::KRIS;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016 NP Broadcast Limited

Kronekeeper is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published
by the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Kronekeeper is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Kronekeeper.  If not, see <http://www.gnu.org/licenses/>.

=cut


use strict;
use warnings;
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use kronekeeper::Activity_Log;
use kronekeeper::Frame qw(
	block_type_id_valid_for_account
);
use kronekeeper::Jumper qw(
	get_connection_count
	pins_are_connected
	add_empty_jumper
	add_jumper_wire
	jumper_template_wire_colour
);
use File::Temp;
use File::Path qw(remove_tree);
use Cwd;
use Parse::CSV;
our $VERSION = '0.01';

my $al = kronekeeper::Activity_Log->new();
my @missing_wiretypes;

prefix '/frame/import/kris' => sub {

	get '/' => require_login sub {

		user_has_role('import') or do {
			send_error('forbidden' => 403);
		};

		my $data = {
			wiretypes => wiretypes(),
			jumper_templates => jumper_templates(),
			block_types => block_types(),
		};

		template('import/kris', $data);
	};	


	post '/krn' => require_login sub {

		# The largest frame encountered at Global Radio is 4.7MB
		# We'll therefore set a limit of 10MB
		my $max_upload_bytes = 10_485_760;
		@missing_wiretypes = ();

		user_has_role('import') or do {
			send_error('forbidden' => 403);
		};

		# Validate parameters
		my $upload = request->upload('file') or do {
			error("ERROR: no file uploaded");
			return krn_error('ERROR_NO_FILE', 400);
		};
		$upload->size or do {
			error("ERROR: uploaded file has zero size");
			return krn_error('ERROR_ZERO_SIZE', 400);
		};
		$upload->size <= $max_upload_bytes or do {
			error("uploaded file exceeds limit of $max_upload_bytes bytes");
			return krn_error('ERROR_TOO_BIG', 413);
		};
		block_type_id_valid_for_account(param('block_type')) or do {
			error("block_type invalid");
			return krn_error('ERROR_INVALID_BLOCK_TYPE', 400);
		};


		# If we have wiretype mappings, commit these to database before processing
		# the KRN file. If there's an error in the KRN processing, at least the
		# wiretype mapping will have been saved and won't have to be re-entered.
		if(param('wiretype_data')) {
			my $wiretype_data = from_json(param('wiretype_data')) or do {
				error("supplied wiretype data is invalid");
				return krn_error('ERROR_INVALID_WIRETYPE_DATA');
			};
			store_wiretypes($wiretype_data) or do {
				error("Failed saving wiretype data mapping");
				return krn_error('ERROR_INVALID_WIRETYPE_DATA');
			};
			database->commit;
		}
		else {
			debug("No wiretype data received, using mapping from database");
		}

		my $frame_id = import_krn(
			$upload->tempname,
			param('block_type')
		) or do {
			error("Failed importing KRN file");
			database->rollback;
			if(@missing_wiretypes) {
				return krn_error("ERROR_UNKNOWN_WIRETYPE");
			}
			return krn_error('ERROR_FAILED_IMPORT');
		};

		# Update Activity Log
		my $note = sprintf(
			'Imported frame from KRIS file [%s]',
			$upload->filename || 'unspecified',
		);
		$al->record({
			function     => 'kronekeeper::Frame::Import::KRIS',
			frame_id     => $frame_id,
			note         => $note,
		});

		database->commit;

		# All ok... display the new frame
		debug("Success! forwarding to /frame/$frame_id");
		forward(
			"/frame/$frame_id",
			{},
			{method => 'GET'},
		);
	};


	post '/wiretype' => require_login sub {

		# We're expecting a small wiretype.def file to be uploaded.
		# Typically these are ~250 bytes, but it depends how many jumper
		# types are defined and how long their descriptions are. As we'll
		# be processing the file in memory, we reject any suspiciously
		# large files.
		my $max_upload_bytes = 4096;

		user_has_role('import') or do {
			send_error('forbidden' => 403);
		};

		my $upload = request->upload('file') or do {
			error("ERROR: no file uploaded");
			return wiretype_error('ERROR_NO_FILE', 400);
		};
		$upload->size or do {
			error("ERROR: uploaded file has zero size");
			return wiretype_error('ERROR_ZERO_SIZE', 400);
		};
		$upload->size <= $max_upload_bytes or do {
			error("uploaded file exceeds limit of $max_upload_bytes bytes");
			return wiretype_error('ERROR_TOO_BIG', 413);
		};

		my $wiretypes = parse_wiretype($upload->content) or do {
			return wiretype_error('ERROR_BAD_FORMAT', 415);
		};
		store_wiretypes($wiretypes);

		database->commit;

		return wiretype_error('SUCCESS');
	};


};



sub krn_error {

	my $krn_error_code = shift;
	my $http_status = shift;

	my $data = {
		wiretypes => wiretypes(),
		krn_error_code => $krn_error_code,
		jumper_templates => jumper_templates(),
		block_types => block_types(),
	};

	$http_status and status($http_status);
	return template('import/kris', $data);
}



sub wiretype_error {

	my $wiretype_error_code = shift;
	my $http_status = shift;

	my $data = {
		wiretypes => wiretypes(),
		wiretype_error_code => $wiretype_error_code,
		jumper_templates => jumper_templates(),
		block_types => block_types(),
	};

	$http_status and status($http_status);
	return template('import/kris', $data);
}



sub parse_wiretype {

	# Parses contents of wiretype.def from KRIS software
	# On error, returns error response directly to client
	# Otherwise returns an arrayref containing a hash for each wiretype

	my $text = shift;
	my @rv = ();

	debug("parsing wiretype data:[$text]");

	# Split file into individual lines
	my @lines = $text =~ m/^(.*?)\s*$/mg;

	# First line should be record count
	my $record_count = shift(@lines);
	$record_count && $record_count =~ m/^\d+$/ or do {
		error("Invalid file format - expected integer record count in first row");
		return undef;
	};

	# Each record is assigned an id in sequence, starting
	# with 0. These ids are referred to by all KRN files
	# on a given installation.
	my $id = 0;

	while($id < $record_count) {

		# Each record comprises three lines:
		#  1) Description of the jumper type
		#  2) a wire colour
		#  3) b wire colour
		#
		# KRIS jumper are always a simple pair - two wires.
		#
		my $name = shift(@lines);

		my $a_colour = parse_colour(shift(@lines)) or do {
			error("Invalid file format. Failed to read a-wire colour for wiretype record $id");
			return undef;
		};

		my $b_colour = parse_colour(shift(@lines)) or do {
			error("Invalid file format. Failed to read b-wire colour for wiretype record $id");
			return undef;
		};

		push(@rv, {
			kris_wiretype_id => $id,
			kris_wiretype_name => $name,
			kris_colour_a => $a_colour,
			kris_colour_b => $b_colour,
		});

		$id ++;
	}

	debug "extracted $record_count wiretype records";
	return \@rv;
}



sub parse_colour {

	my $text = shift;
	$text or return undef;

	# extract hex digits
	my ($hex) = $text =~ m/^\&H([0-9a-f]+)\&$/i or return undef;

	# zero pad to 6 digits
	$hex = sprintf("%06s", $hex);

	# Swap byte order to match html RRGGBB
	$hex =~ s/(..)(..)(..)/$3$2$1/;

	return $hex;
}



sub store_wiretypes {

	my $wiretypes = shift;
	my $account_id = session('account')->{id};

	# Clear existing wiretypes
	my $q = database->prepare("
		DELETE FROM kris.jumper_type
		WHERE account_id = ?
	");
	$q->execute($account_id);

	# Insert each new wiretype in turn
	$q = database->prepare("
		INSERT INTO kris.jumper_type(
			account_id,
			kris_wiretype_id,
			name,
			a_wire_colour_code,
			b_wire_colour_code,
			jumper_template_id
		)
		VALUES (?,?,?,DECODE(?, 'hex'),DECODE(?, 'hex'),?)
	");

	foreach my $wiretype(@{$wiretypes}) {

		# If specified, confirm jumper_template_id is valid for this account
		if($wiretype->{jumper_template_id}) {
			jumper_template_id_valid_for_account(
				$wiretype->{jumper_template_id}
			) or do {
				database->rollback;
				error("jumper_template_id is not valid for this account");
				send_error("jumper_template_id is not valid for this account");
			};
		}	

		# Strip any leading '#' from the colour codes
		my $colour_a = $wiretype->{kris_colour_a} =~ s/^#//;
		my $colour_b = $wiretype->{kris_colour_b} =~ s/^#//;

		my @values = (
			$account_id,
			$wiretype->{kris_wiretype_id},
			$wiretype->{kris_wiretype_name},
			$wiretype->{kris_colour_a},
			$wiretype->{kris_colour_b},
			$wiretype->{jumper_template_id},
		);

		$q->execute(@values) or do {
			database->rollback;
			error("ERROR writing wiretype record to database");
			send_error("ERROR writing wiretype record to database");
		};
	}

	return 1;
}



sub jumper_template_id_valid_for_account {

	my $jumper_template_id = shift;
	my $account_id = shift || session('account')->{id};

	$jumper_template_id && $jumper_template_id =~ m/^\d+$/ or do {
		error "jumper_template_id is not an integer: [$jumper_template_id]";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM jumper_template
		WHERE jumper_template.account_id = ?
		AND jumper_template.id = ?
	");
	$q->execute(
		$account_id,
		$jumper_template_id
	);

	return $q->fetchall_arrayref({});
}



sub wiretypes {

	# Note that KRIS wiretypes are always two-wire pairs
	my $account_id = session('account')->{id};
	my $q = database->prepare("
		SELECT
			jumper_type.id,
			jumper_type.kris_wiretype_id,
			jumper_type.name AS kris_wiretype_name,
			CONCAT('#', ENCODE(jumper_type.a_wire_colour_code, 'hex')) AS kris_colour_a,
			CONCAT('#', ENCODE(jumper_type.b_wire_colour_code, 'hex')) AS kris_colour_b,
			jumper_template.id AS jumper_template_id
		FROM kris.jumper_type
		LEFT JOIN jumper_template ON (
			jumper_template.id = jumper_template_id
			AND jumper_template_wire_count(jumper_template.id) = 2
		)
		WHERE jumper_type.account_id = ?
		ORDER BY kris_wiretype_id
	");
	$q->execute($account_id);
	return $q->fetchall_arrayref({});
}



sub jumper_templates {

	# KRIS jumpers are always two-wire pairs
	# This returns two-wire jumper templates for this specific purpose
	my $account_id = session('account')->{id};
	my $q = database->prepare("
		SELECT 
			jumper_template.id,
			jumper_template.name,

			a_colour.name AS a_colour_name,
			CONCAT('#', ENCODE(a_colour.html_code, 'hex')) AS a_colour_code,
			CONCAT('#', ENCODE(a_colour.contrasting_html_code, 'hex')) AS a_contrasting_colour_code,

			b_colour.name AS b_colour_name,
			CONCAT('#', ENCODE(b_colour.html_code, 'hex')) AS b_colour_code,
			CONCAT('#', ENCODE(b_colour.contrasting_html_code, 'hex')) AS b_contrasting_colour_code

		FROM jumper_template
		JOIN jumper_template_wire AS a_wire ON (
			a_wire.jumper_template_id = jumper_template.id
			AND a_wire.position = 1
		)
		JOIN colour AS a_colour ON (
			a_colour.id = a_wire.colour_id
		)
		JOIN jumper_template_wire AS b_wire ON (
			b_wire.jumper_template_id = jumper_template.id
			AND b_wire.position = 2
		)
		JOIN colour AS b_colour ON (
			b_colour.id = b_wire.colour_id
		)

		WHERE jumper_template.account_id = ?
		AND jumper_template_wire_count(jumper_template.id) = 2 

		ORDER BY jumper_template.name	
	");
	$q->execute($account_id);
	return $q->fetchall_arrayref({});
}


sub block_types {

	# KRIS frames have only a single block type, having
	# 10 pairs. We need to select which kronekeeper block
	# type to use when importing the frame. This returns
	# all available 10-pair block types for selection.

	my $account_id = shift || session('account')->{id};
	my $q = database->prepare("
		SELECT id, name
		FROM block_type
		WHERE block_type.account_id = ?
		AND circuit_count = 10
		AND circuit_pin_count = 2
		ORDER BY name ASC
	");
	$q->execute($account_id);
	return $q->fetchall_arrayref({});
}



sub import_krn {

	my $filename = shift;
	my $block_type_id = shift;
	my $frame_id = undef;
	debug("Received KRN file: $filename");

	# We need to create a temporary directory to extract the KRN file tables
	my $temp = File::Temp->newdir();
	my $original_dir = cwd();
	my $dir = $temp->dirname;
	debug("Original working dir: $original_dir");
	debug("Using tempdir: $dir");

	chdir($dir) or do {
		error("ERROR changing to temporary working directory");
		goto CLEANUP;
	};

	# Build krn2csv command
	config->{wine} or do {
		error("path to wine executable is not defined in the kronekeeper configuration file");
		goto CLEANUP;
	};
	config->{krn_to_csv} or do {
		error("path to krn_to_csv executable is not defined in the kronekeeper configuration file");
		goto CLEANUP;
	};
	my $command = sprintf(
		"DISPLAY=:1 %s %s %s",
		config->{wine},
		config->{krn_to_csv},
		$filename,
	);
	debug("using command: $command");

	# Run krn2csv command
	system $command and do {
		error("ERROR running krn_to_csv command");
		goto CLEANUP;
	};


	# We now have a directory of CSV files...
	my $info = read_kris_info($dir) or do {
		goto CLEANUP;
	};

	# Load CSV data into temporary database tables
	import_circuits($dir)      and
	import_blocks($dir, $info) and
	import_cctlu($dir)         and
	import_jumpers($dir) or do {
		error("ERROR loading KRIS CSV data into database");
		database->rollback;
		goto CLEANUP;
	};

	# Create Kronekeeper entities from imported data
	$frame_id = create_entities($info, $block_type_id) or do {
		error("Failed creating Kronekeeper entities from imported KRN data");
		database->rollback;
		goto CLEANUP;
	};
	
	CLEANUP:
	chdir($original_dir) or do {
		error("ERROR changing back to original working directory $!");
	};
	remove_tree($dir) or do {
		error("ERROR: failed to remove temporary diretory $dir $!");
	};

	return $frame_id;
}



sub read_kris_info {

	my $dir = shift;
	my $file = "$dir/Info.csv";
	debug("importing $file...");

	my $csv = Parse::CSV->new(
		file => $file,
		names => [
			'columns',
			'blocks',
			'col_alpha',
			'block_alpha',
			'job_num',
			'job_title',
			'area',
			'software_revision',
			'lock',
			'lock_pass',
		],
	) or do {
		return error_and_rollback("ERROR opening $file");
	};

	my $info = $csv->fetch or do {
		return error_and_rollback("failed reading KRIS info record");
	};

	# Validation and sanity checks...
	debug("        job_title: $info->{job_title}");
	debug("       job_number: $info->{job_num}");
	debug("             area: $info->{area}");
	debug("          columns: $info->{columns}");
	debug("           blocks: $info->{blocks}");
	debug("software revision: $info->{software_revision}");

	$info->{col_alpha}   and warning("SURPRISE: KRIS col_alpha is not false [$info->{col_alpha}]");
	$info->{block_alpha} and warning("SURPRISE: KRIS block_alpha is not false [$info->{col_alpha}]");
	$info->{lock}        and warning("SURPRISE: KRIS frame is marked as locked - proceeding anyway");

	unless($info->{columns} && $info->{columns} =~ m/^[1-9]\d*$/) {
		error_and_rollback("column count is invalid: [$info->{columns}]");
	}
	unless($info->{blocks} && $info->{blocks} =~ m/^[1-9]\d*$/) {
		error_and_rollback("column count is invalid: [$info->{blocks}]");
	}

	return $info;
}


# It would be faster for postgresql to directly import the csv files, but
# that gets us a world of permissions grief. Much easier instead to read
# csv files from perl and pass line-by-line to the database.


sub import_circuits {

	my $dir = shift;
	my $file = "$dir/Circuits.csv";
	my $count = 0;
	debug("importing $file...");

	database->do("
		CREATE TEMPORARY TABLE kris_circuits (
			Circuit_Number INTEGER PRIMARY KEY,
			Title          TEXT,     --always NULL?
			Cable          TEXT,     --maps to Kronekeeper circuit.cable field
			Connection     TEXT,     --maps to Kronekeeper circuit.connection field
			TempLevel      INTEGER,  --always NULL?
			kronekeeper_circuit_id INTEGER
		)
		ON COMMIT DROP
	") or do {
		return error_and_rollback("ERROR creating temporary table kris_jumpers");
	};

	my $q = database->prepare("
		INSERT INTO kris_circuits (
			Circuit_Number,
			Title,
			Cable,
			Connection,
			TempLevel
		) VALUES (?, TRIM(?), TRIM(?), TRIM(?), ?)
	");

	my $csv = Parse::CSV->new(
		file => $file
	) or do {
		return error_and_rollback("ERROR opening $file");
	};

	while(my $data = $csv->fetch) {
		# TempLevel is an integer field, but if it's NULL appears as empty string in
		# the CSV file. We therefore translate empty string into NULL before importing
		# into the database, otherwise it will choke on a non-integer value.
		defined $$data[4] && $$data[4] eq "" and $$data[4] = undef;

		# In all the KRN files we've examined, TempLevel has been NULL. Raise a warning
		# if this condition isn't met, so we can investigate a new twist to the file format
		defined $$data[4] and do {
			warning("UNEXPECTED: KRIS Circuits.TempLevel field is NOT NULL");
		};

		$q->execute(@{$data}) or do {
			return error_and_rollback("ERROR writing kris_circuits data to database", join(":", @{$data}));
		};
		$count ++;
	};

	debug("read $count circuits from $file");
	return 1;
}


sub import_blocks {

	my $dir = shift;
	my $info = shift;
	my $file = "$dir/Blocks.csv";
	my $count = 0;
	debug("importing $file...");

	database->do("
		CREATE TEMPORARY TABLE kris_blocks (
			Block_Ref   TEXT,          --maps to kronekeeper designation e.g. 'A01'
			Block_Title TEXT,          --maps to kronekeeper block.name
			CCT1        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT2        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT3        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT4        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT5        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT6        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT7        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT8        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT9        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			CCT0        INTEGER NOT NULL REFERENCES kris_circuits(Circuit_Number),
			Block_Num   INTEGER,       --indicating groupings?
			Block_Of    INTEGER,       --indicating groupings?
			Link_File   TEXT,          --always NULL?
			Link_Block  TEXT,          --always NULL?
			kronekeeper_block_id INTEGER
		)
		ON COMMIT DROP
	") or return error_and_rollback("ERROR creating temporary table kris_jumpers");
	database->do("
		CREATE UNIQUE INDEX kris_blocks_reference_idx ON kris_blocks(Block_Ref)
	") or return error_and_rollback("ERROR creating index on kris_blocks(Block_Ref)");
	database->do("
		CREATE UNIQUE INDEX kris_blocks_kk_block_id_idx ON kris_blocks(kronekeeper_block_id)
	") or return error_and_rollback("ERROR creating index on kris_blocks(kronekeeper_block_id)");

	# We've encountered some corrupt KRIS files with duplicate Block records
	# This stored procedure ignores them to allow the import to proceed.
	# Postgresql >9.5 has this feature built-in, but we're using an earlier version
	# so have to handle this ourselves.
	database->do("
		CREATE OR REPLACE RULE kris_blocks_ignore_duplicate_inserts AS
			ON INSERT TO kris_blocks
			WHERE (EXISTS (
				SELECT 1
				FROM kris_blocks
				WHERE kris_blocks.Block_Ref = NEW.Block_Ref
			))
			DO INSTEAD NOTHING;
	") or return error_and_rollback("ERROR creating trigger to prevent duplicate kris_blocks.Block_Ref");

	my $q = database->prepare("
		INSERT INTO kris_blocks (
			Block_Ref,
			Block_Title,
			CCT1,
			CCT2,
			CCT3,
			CCT4,
			CCT5,
			CCT6,
			CCT7,
			CCT8,
			CCT9,
			CCT0,
			Block_Num,
			Block_Of,
			Link_File,
			Link_Block
		) VALUES(?,TRIM(?),?,?,?,?,?,?,?,?,?,?,?,?,?,?)
	");

	my $csv = Parse::CSV->new(
		file => $file
	) or do {
		return error_and_rollback("ERROR opening $file");
	};

	while(my $data = $csv->fetch) {

		# Still trying to work out the purpose of Link_File and Link_Block fields
		# they are numeric, but can sometimes be NULL. In the CSV file, NULL numbers
		# are encoded as "", so we need to translate those to NULL before inserting
		# into the database
		defined $$data[12] && $$data[12] eq "" and $$data[12] = undef;
		defined $$data[13] && $$data[13] eq "" and $$data[13] = undef;

		$q->execute(@{$data}) or do {
			return error_and_rollback("ERROR writing kris_block data to database", join(":", @{$data}));
		};
		$count ++;
	};

	debug("read $count blocks from $file");

	# KRN files allocate every block position - there is no concept of an 'empty' frame position
	my $expected_block_count = $info->{blocks} * $info->{columns};
	unless($count == $expected_block_count) {
		return error_and_rollback("block count does not match frame size");
	}
	
	return 1;
}


sub import_cctlu {

	my $dir = shift;
	my $file = "$dir/CCTLU.csv";
	my $count = 0;
	debug("importing $file...");

	database->do("
		CREATE TEMPORARY TABLE kris_cctlu (
			cct_title_ref  INTEGER PRIMARY KEY, --referenced by kris_jumpers.cct_title_lu
			cct_title_text TEXT
		)
		ON COMMIT DROP
	") or do {
		return error_and_rollback("ERROR creating temporary table kris_cctlu");
	};

	my $q = database->prepare("
		INSERT INTO kris_cctlu(
			cct_title_ref,
			cct_title_text
		)
		VALUES(?, TRIM(?))
	");

	my $csv = Parse::CSV->new(
		file => $file
	) or do {
		return error_and_rollback("ERROR opening $file");
	};

	while(my $data = $csv->fetch) {
		$q->execute(@{$data}) or do {
			return error_and_rollback("ERROR writing kris_jumper data to database", join(":", @{$data}));
		};
		$count ++;
	};

	debug("read $count cctlu records from $file");

	return 1;
}


sub import_jumpers {

	my $dir = shift;
	my $file = "$dir/Jumpers.csv";
	my $count = 0;
	debug("importing $file...");

	database->do("
		CREATE TEMPORARY TABLE kris_jumpers (
			SRC_CCT      INTEGER REFERENCES kris_circuits(Circuit_Number),
			DEST_CCT     INTEGER REFERENCES kris_circuits(Circuit_Number),
			Created      TIMESTAMP,     --ignored by Kronekeeper
			CE_Create    BOOLEAN,       --ignored by Kronekeeper, indicates if Clyde Electronics made this jumper entry
			Jumper_Num   INTEGER,       --incrementing Primary Key
			Other_Way    INTEGER,       --references 'reverse' row Jumpers.JumperNum
			SRC_Block    TEXT,          --Block full designation, references Blocks.BlockRef
			DEST_Block   TEXT,          --Block full designation, references Blocks.BlockRef
			CCT_Title    TEXT,          --always NULL?
			Insert_Processed BOOLEAN,   --normally True - flag indicates if jumper been physically wired
			CCT_Title_LU INTEGER REFERENCES kris_cctlu(cct_title_ref), --use this to access circuit name
			Split        INTEGER,       --normally 0, otherwise code indicates wire split - a>a a>b etc...
			Wire         INTEGER,       --references jumper colour defined in external wiretype.def file
			Defer_Group  INTEGER        --always -1
		)
		ON COMMIT DROP
	") or do {
		return error_and_rollback("ERROR creating temporary table kris_jumpers");
	};

	my $q = database->prepare("
		INSERT INTO kris_jumpers(
			SRC_CCT,
			DEST_CCT,
			Created,
			CE_Create,
			Jumper_Num,
			Other_Way,
			SRC_Block,
			DEST_Block,
			CCT_Title,
			Insert_Processed,
			CCT_Title_LU,
			Split,
			Wire,
			Defer_Group
		) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)
	");

	my $csv = Parse::CSV->new(
		file => $file
	) or do {
		return error_and_rollback("ERROR opening $file");
	};

	while(my $data = $csv->fetch) {
		debug join("::", @{$data});
		# Clean Defer_Group - we've encountered some files where this has garbage data
		$$data[13] =~ m/^-?\d+$/ or do {
			warning("encountered bad Jumpers.Defer_Group value - ignoring");
			$$data[13] = undef;
		};

		$q->execute(@{$data}) or do {
			return error_and_rollback("ERROR writing kris_jumper data to database", join(":", @{$data}));
		};
		$count ++;
	};

	debug("read $count jumpers from $file");

	dump_wiretypes();

	validate_wiretype_mapping() or do {
		return error_and_rollback("failed validation of wiretype mapping");
	};

	return 1;
}



sub validate_wiretype_mapping {

	# This function updates global @missing_wiretypes if any wiretypes are missing
	debug("checking KRIS Wiretypes are mapped to a Kronekeeper jumper_template");

	# Locate any KRIS Wiretypes without Kronekeeper jumper template mapping
	my $q = database->prepare("
		SELECT DISTINCT Wire AS wiretype
		FROM kris_jumpers
		WHERE NOT EXISTS (
			SELECT 1 FROM kris.jumper_type
			WHERE kris.jumper_type.kris_wiretype_id = kris_jumpers.Wire
			AND kris.jumper_type.account_id = ?
			AND kris.jumper_type.jumper_template_id IS NOT NULL
		)
	");
	$q->execute(
		session('account')->{id}
	);
	my $result = $q->fetchall_hashref('wiretype');
	@missing_wiretypes = keys(%{$result});

	if(@missing_wiretypes) {
		error(sprintf(
			"ERROR: Found KRIS Wiretypes %s without Kronekeeper jumper_template mappings",
			join(",", @missing_wiretypes)
		));
		return 0;
	}

	# Otherwise all OK
	debug("all KRIS Wiretypes are mapped to a Kronekeeper jumper_template");
	return 1;
}


sub create_entities {

	my $info = shift;
	my $block_type_id = shift;
	my $account_id = session('account')->{id};

	my $frame_id = create_frame($info) or return undef;

	map_block_ids($frame_id) &&
	place_blocks($block_type_id) &&
	apply_block_labels() &&
	apply_circuit_labels() &&
	apply_jumpers() &&
	remove_inactive_blocks($frame_id) or return undef;

	return $frame_id;
}


sub create_frame {

	my $info = shift;
	my $account_id = session('account')->{id};

	my $frame_name = "$info->{job_title} : $info->{area}";
	debug("creating frame [$frame_name]");

	# Kris frame designations always run left-right, bottom-top
	my $q = database->prepare("
		SELECT create_regular_frame(?,?,?,?,?,?,?) AS new_frame_id
	");
	$q->execute(
		$account_id,
		$frame_name,
		$info->{columns},
		$info->{blocks},
		'f', # don't reverse horizontal designations
		'f', # don't reverse vertical designations
		'f', # not a template frame
	) or do {
		return error_and_rollback("ERROR running create_regular_frame on database");
	};
	my $r = $q->fetchrow_hashref or do {
		return error_and_rollback("ERROR no result after running create_regular_frame on database");
	};

	debug("created new frame with id: ", $r->{new_frame_id});
	return $r->{new_frame_id};
}


sub map_block_ids {

	debug("mapping block_ids");
	my $frame_id = shift;
	my $q = database->prepare("
		UPDATE kris_blocks
		SET kronekeeper_block_id = c_designation_to_block_id(?, Block_Ref)
	");
	$q->execute($frame_id) or return_error_and_rollback("ERROR mapping block_ids");
}


sub place_blocks {

	debug("placing blocks");
	my $block_type_id = shift;
	my $q = database->prepare("
		SELECT place_generic_block_type(kronekeeper_block_id, ?)
		FROM kris_blocks
	");
	$q->execute($block_type_id) or return error_and_rollback("ERROR placing blocks");
}


sub apply_block_labels {

	debug("applying block_labels");
	my $q = database->do("
		UPDATE block
		SET name = Block_Title
		FROM kris_blocks
		WHERE block.id = kronekeeper_block_id
		AND Block_Title IS NOT NULL
		AND Block_Title != ''
	") or return error_and_rollback("ERROR updaing Kronekeeper block names from KRIS data");
}


sub apply_circuit_labels {

	debug("applying circuit_labels");
	# We'll do this block-by-block
	# Updates kris_circuits.kronekeeper_circuit_id field
	my $q = database->prepare("SELECT * from kris_blocks");
	$q->execute();

	my $update_circuit = database->prepare("
		UPDATE circuit
		SET
			cable_reference = kris_circuits.Cable,
			connection = kris_circuits.Connection
		FROM kris_circuits
		WHERE kris_circuits.Circuit_Number = ?
		AND circuit.block_id = ?
		AND circuit.position = ?
	");

	my $update_circuit_id = database->prepare("
		UPDATE kris_circuits
		SET kronekeeper_circuit_id = circuit.id
		FROM circuit
		WHERE kris_circuits.Circuit_Number = ?
		AND circuit.block_id = ?
		AND circuit.position = ?
	");

	my %circuit_map = (
		 1 => 'cct0',
		 2 => 'cct1',
		 3 => 'cct2',
		 4 => 'cct3',
		 5 => 'cct4',
		 6 => 'cct5',
		 7 => 'cct6',
		 8 => 'cct7',
		 9 => 'cct8',
		10 => 'cct9',
	);

	while(my $kris_block = $q->fetchrow_hashref()) {

		#use Data::Dumper;
		#debug("processing kris block: $kris_block->{block_ref}");
		#debug(Dumper $kris_block);

		# A KRIS block record has a field for each of the
		# 10 circuits. Process each of these in turn
		foreach my $position(keys %circuit_map) {

			my $kris_field = $circuit_map{$position};

			#debug("    processing position: $position");
			#debug("             kris_field: $kris_field");
			#debug("        kris_circuit_id: $kris_block->{$kris_field}");
			#debug("      kronekeeper block: $kris_block->{kronekeeper_block_id}");
			#debug("               position: $position");

			$update_circuit->execute(
				$kris_block->{$kris_field},
				$kris_block->{kronekeeper_block_id},
				$position,
			) or return error_and_rollback("ERROR updating Kronekeeper circuit from KRIS data");

			$update_circuit_id->execute(
				$kris_block->{$kris_field},
				$kris_block->{kronekeeper_block_id},
				$position,
			) or return error_and_rollback("ERROR updating Kronekeeper circuit from KRIS data");
		}
	}

	# Finally update all the circuit names - which come from a separate lookup table
	database->do("
		UPDATE circuit
		SET name = kris_cctlu.cct_title_text
		FROM kris_jumpers
		JOIN kris_circuits ON (
			SRC_CCT = kris_circuits.Circuit_Number
			OR DEST_CCT = kris_circuits.Circuit_Number
		)
		LEFT JOIN kris_cctlu ON (
			kris_cctlu.cct_title_ref = kris_jumpers.CCT_Title_LU
		)
		WHERE circuit.id = kris_circuits.kronekeeper_circuit_id
	") or return error_and_rollback("ERROR mapping circuit names");


	return 1;
}


sub apply_jumpers {

	debug("applying jumpers");
	my $account_id = session('account')->{id};
	my $q = database->prepare("
		SELECT
			SRC_CCT,
			c1.kronekeeper_circuit_id AS a_kk_circuit_id,
			DEST_CCT,
			c2.kronekeeper_circuit_id AS b_kk_circuit_id,
			SRC_Block,
			DEST_Block,
			CCT_Title,
			Split,
			Wire,
			jumper_template_id
		FROM kris_jumpers
		JOIN kris_circuits AS c1 ON (
			c1.Circuit_Number = kris_jumpers.SRC_CCT
		)
		JOIN kris_circuits AS c2 ON (
			c2.Circuit_Number = kris_jumpers.DEST_CCT
		)
		JOIN kris.jumper_type ON (
			jumper_type.account_id = ?
			AND jumper_type.kris_wiretype_id = Wire			
		)
	");
	$q->execute($account_id);

	# Rather than looping, we could arguably do this in a single database
	# query, but debugging is easier processing one-by-one
	while( my $jumper = $q->fetchrow_hashref() ) {

		#use Data::Dumper;
		#debug(Dumper $jumper);

		# Insert jumper of the appropriate type
		unless(defined $jumper->{split} && $jumper->{split} =~ m/^\d+$/) {
			return error_and_rollback("invalid jumper->split type");
		}
		if($jumper->{split} == 0) {
			insert_simple_jumper($jumper) or do {
				return error_and_rollback("ERROR adding simple jumper");
			};
		}
		else {
			insert_complex_jumper($jumper) or do {
				return error_and_rollback("ERROR adding complex jumper");
			};
		}
	}
	return 1;
}


sub insert_simple_jumper {

	my $jumper = shift;

	# Check if a jumper already exists. KRN data
	# includes each jumper twice... once in each direction,
	# so it's normal to find duplicates.
	my $connections = get_connection_count(
		$jumper->{a_kk_circuit_id},
		$jumper->{b_kk_circuit_id},
	);
	if($connections->{complex}->{connection_count}) {
		return error_and_rollback(
			"KRIS data calls for a simple jumper where a complex jumper type already exists"
		);
	}
	if($connections->{simple}->{connection_count}) {
		debug("jumper already exists - skipping");
		return 1;
	}

	# simple jumper
	my $insert_jumper = database->prepare("
		SELECT add_simple_jumper(?,?,?) AS jumper_id
	");
	$insert_jumper->execute(
		$jumper->{a_kk_circuit_id},
		$jumper->{b_kk_circuit_id},
		$jumper->{jumper_template_id},
	) or do {
		return error_and_rollback("failed to insert jumper");
	};
}


sub insert_complex_jumper {

	my $jumper = shift;

	# KRIS jumpers specify a 'split' code where they are not
	# a simple pair connection. These split jumpers are only
	# ever a single wire
	my @split_pins = (
		undef,  # type 0 : standard simple jumper
		[1 => 1], # type 1 a->a
		[1 => 2], # type 2 a->b
		[2 => 1], # type 3 b->a
		[2 => 2], # type 4 b->b
	);
	my($a_pin_position, $b_pin_position) = @{$split_pins[$jumper->{split}]} or do {
		error("invalid jumper->split type");
		return undef;		
	};

	# Get pin ids
	my $a_pin_id = get_pin_id(
		$jumper->{a_kk_circuit_id},
		$a_pin_position,
	);
	my $b_pin_id = get_pin_id(
		$jumper->{b_kk_circuit_id},
		$b_pin_position,
	);
	$a_pin_id && $b_pin_id or do {
		error("ERROR extracting pin ids");
	};

	# Already connected?
	if(pins_are_connected($a_pin_id, $b_pin_id)) {
		debug("pins are already connected");
		return 1;
	}
	
	# Get colour
	my $colour_id = jumper_template_wire_colour(
		$jumper->{jumper_template_id},
		$a_pin_position,
	) or return undef;
	debug("got wire colour: [$colour_id]");

	# Place jumper
	my $new_jumper_id = add_empty_jumper() or return undef;
	add_jumper_wire(
		$new_jumper_id,
		{
			a_pin_id => $a_pin_id,
			b_pin_id => $b_pin_id,
			wire_colour_id => $colour_id,
		}
	) or return undef;
}


sub get_pin_id {

	my $circuit_id = shift;
	my $pin_position = shift;

	debug("looking up pin id for circuit_id:[$circuit_id] position:[$pin_position]");
	
	my $q = database->prepare("
		SELECT id
		FROM pin
		WHERE circuit_id = ?
		AND position = ?
	");
	$q->execute(
		$circuit_id,
		$pin_position,
	);
	
	my $result= $q->fetchrow_hashref() or do {
		error("failed looking up pin_id");
		return undef;
	};
	debug("pin_id: $result->{id}");
	return $result->{id};
}


sub remove_inactive_blocks {

	# In KRIS all possible blocks in the frame are
	# populated and of the same type. In Kronekeeper,
	# we keep track of which positions are empty.
	#
	# Once all the KRIS blocks are imported, remove any
	# blocks which are inactive... no jumpers, and all
	# text fields empty

	my $frame_id = shift;
	debug("removing inactive blocks");
	my $q = database->prepare("
		SELECT remove_block(block.id)
		FROM block
		JOIN vertical ON (vertical.id = block.vertical_id)
		WHERE vertical.frame_id = ?
		AND (
			block.name IS NULL
			OR block.name = ''
		)
		AND NOT EXISTS (
			SELECT 1
			FROM circuit
			WHERE circuit.block_id = block.id
			AND (
				circuit.name != ''
				OR circuit.cable_reference != ''
				OR circuit.connection != ''
				OR circuit.note != ''
			)
		)
		AND NOT EXISTS (
			SELECT 1
			FROM connection
			JOIN pin ON (
				pin.id = connection.pin_id
			)
			JOIN circuit ON (
				circuit.id = pin.circuit_id
			)
			WHERE circuit.block_id = block.id
		)
	");
	$q->execute($frame_id);

}
		

sub dump_wiretypes {

	debug("analysing Wiretypes...");
	my $q = database->prepare("
		SELECT Wire AS w, COUNT(*) AS c
		FROM kris_jumpers
		GROUP BY w
		ORDER BY w
	");
	$q->execute;
	while(my $r = $q->fetchrow_hashref) {
		debug("Wiretype $r->{w} used by $r->{c} jumpers");
	}
}


sub error_and_rollback{
	my $message = shift;
	error($message);
	database->rollback;
	return undef;
}








1;
