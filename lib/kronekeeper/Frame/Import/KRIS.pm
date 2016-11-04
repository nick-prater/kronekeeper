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

use Data::Dumper;
debug Dumper $data;

		template('import/kris', $data);
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
			send_error('missing file upload' => 400);
		};
		$upload->size or do {
			send_error('uploaded file has zero size' => 400);
		};
		$upload->size <= $max_upload_bytes or do {
			send_error("uploaded file exceeds limit of $max_upload_bytes bytes" => 413);
		};

		my $wiretypes = parse_wiretype($upload->content);
		store_wiretypes($wiretypes);

		database->commit;

		use Data::Dumper;
		return Dumper $wiretypes;
	};


};




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
		send_error(
			"Invalid file format - expected integer record count in first row",
			415
		);
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
			send_error(
				"Invalid file format. Failed to read a-wire colour for wiretype record $id",
				415
			);
		};

		my $b_colour = parse_colour(shift(@lines)) or do {
			send_error(
				"Invalid file format. Failed to read b-wire colour for wiretype record $id",
				415
			);
		};

		#debug "$id :: $name : $a_colour : $b_colour";
		push(@rv, {
			id => $id,
			name => $name,
			a_colour => $a_colour,
			b_colour => $b_colour,
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
			b_wire_colour_code
		)
		VALUES (?,?,?,DECODE(?, 'hex'),DECODE(?, 'hex'))
	");

	foreach my $wiretype(@{$wiretypes}) {
		$q->execute(
			$account_id,
			$wiretype->{id},
			$wiretype->{name},
			$wiretype->{a_colour},
			$wiretype->{b_colour},
		) or do {
			error("ERROR writing wiretype record to database");
		};
	}	
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




























1;
