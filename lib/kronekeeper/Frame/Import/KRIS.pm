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
use File::Temp;
use File::Path qw(remove_tree);
use Cwd;
use Parse::CSV;
our $VERSION = '0.01';

my $al = kronekeeper::Activity_Log->new();


prefix '/frame/import/kris' => sub {

	get '/' => require_login sub {

		user_has_role('import') or do {
			send_error('forbidden' => 403);
		};

		my $data = {
			wiretypes => wiretypes(),
			jumper_templates => jumper_templates(),
		};

		template('import/kris', $data);
	};	


	post '/krn' => require_login sub {

		# The largest frame encountered at Global Radio is 4.7MB
		# We'll therefore set a limit of 10MB
		my $max_upload_bytes = 10_485_760;

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

		import_krn($upload->tempname);

		return krn_error('ERROR_FAILED_IMPORT', 500);
		return krn_error('SUCCESS');
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
	# with 1. These ids are referred to by all KRN files
	# on a given installation.
	my $id = 1;

	while($id <= $record_count) {

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



sub import_krn {

	my $filename = shift;
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
	my $command = sprintf(
		"DISPLAY=:1 wine32 %s %s",
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
	# Load CSV data into temporary database tables
	import_jumpers($dir) or do {
		error("ERROR loading KRIS CSV data into database");
		database->rollback;
		goto CLEANUP;
	};

	# Before we get carried away, make sure we can map every KRIS wiretype,
	# which is essential for a successful import. The check is quick to do
	# and allows us to bail-out early if we don't have the information we need.




	CLEANUP:
	chdir($original_dir) or do {
		error("ERROR changing back to original working directory $!");
	};
	remove_tree($dir) or do {
		error("ERROR: failed to remove temporary diretory $dir $!");
	};

}


sub import_jumpers {

	my $dir = shift;
	my $file = "$dir/Jumpers.csv";
	my $count = 0;
	debug("importing $file...");

	database->do("
		CREATE TEMPORARY TABLE kris_jumpers (
			SRC_CCT      INTEGER,       --references Circuits.Circuit_Number
			DEST_CCT     INTEGER,       --references Circuits.Circuit_Number
			Created      TIMESTAMP,     --ignored by Kronekeeper
			CE_Create    BOOLEAN,       --ignored by Kronekeeper, indicates if Clyde Electronics made this jumper entry
			Jumper_Num   INTEGER,       --incrementing Primary Key
			Other_Way    INTEGER,       --references 'reverse' row Jumpers.JumperNum
			SRC_Block    TEXT,          --Block full designation, references Blocks.BlockRef
			DEST_Block   TEXT,          --Block full designation, references Blocks.BlockRef
			CCT_Title    TEXT,          --always NULL?
			Insert_Processed BOOLEAN,   --normally True - flag indicates if jumper been physically wired
			CCT_Title_LU INTEGER,       --ignored by Kronekeeper, references CCTLU.CCT Title Ref
			Split        INTEGER,       --normally 0, otherwise code indicates wire split - a>a a>b etc...
			Wire         INTEGER,       --references jumper colour defined in external wiretype.def file
			Defer_Group  INTEGER        --always -1
		)
		ON COMMIT DROP
	") or do {
		error("ERROR creating temporary table kris_jumpers");
		database->rollback;
		return 0;
	};

	# It would be faster for postgresql to directly import the csv file, but
	# that gets us a world of permissions grief. Much easier instead to read
	# csv file from perl and pass line-by-line to the database.

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
		error("ERROR opening $file");
		database->rollback;
		return 0;
	};

	while(my $data = $csv->fetch) {
		$q->execute(@{$data}) or do {
			error("ERROR writing kris_jumper data to database", join(":", @{$data}));
			database->rollback;
			return 0;
		};
		$count ++;
	};


	debug("read $count jumpers from $file");
	return 1;
}





















1;
