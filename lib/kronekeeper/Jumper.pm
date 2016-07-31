package kronekeeper::Jumper;

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
use feature 'switch';
use Dancer2 appname => 'kronekeeper';
use Dancer2::Plugin::Database;
use Dancer2::Plugin::Auth::Extensible;
use kronekeeper::Activity_Log;
use kronekeeper::Circuit qw(
	circuit_info
	circuit_info_from_designation
	circuit_pins
	circuit_id_valid_for_account
);
use List::Util qw(max);

my $al = kronekeeper::Activity_Log->new();


prefix '/jumper' => sub {

	post '/connection_choice' => require_login sub {

		debug("connection_choice");
		debug( request->body);

		# jumper_id is an optional parameter giving
		# the id of a jumper we might be replacing, so
		# we can exclude it from collision checks.
		if(param("replacing_jumper_id") && !jumper_id_valid_for_account(param("replacing_jumper_id"))) {
			send_error('Access to requested jumper_id is forbidden.' => 403);
		}

		# a_circuit_id is the starting point for this jumper - required parameter
		unless(defined param("a_circuit_id")) {
			send_error('Missing a_circuit_id parameter.' => 400);
		}
		unless(circuit_id_valid_for_account(param("a_circuit_id"))) {
			send_error('Bad circuit_id. Forbidden' => 403);
		}
		my $a_circuit_info = circuit_info(param("a_circuit_id"));
		
		# b_designation is the human readable destination circuit - required parameter
		unless(defined param("b_designation")) {
			send_error('Missing b_designation parameter.' => 400);
		}
		my $b_circuit_info = circuit_info_from_designation(
			param("b_designation"),
			$a_circuit_info->{frame_id},
		) or do {
			error('b_designation parameter is not a valid circuit on this frame');
			return template(
				'jumper/invalid',
				{
					error_code => 'INVALID_CIRCUIT',
					b_designation => prettify_designation(param("b_designation")),
				},
				{ layout => undef }
			);
		};

		debug("considering jumper linking circuit_id $a_circuit_info->{id} -> $b_circuit_info->{id}");
		my $connections = get_connection_count(
			$a_circuit_info->{id},
			$b_circuit_info->{id},
			param("replacing_jumper_id"),
		);

		# Is there already a simple jumper between starting point and destination?
		# If so, we cannot add any more connections
		if($connections->{simple}->{connection_count}) {
			debug("cannot add more jumpers between these circuits - a simple jumper already links them");
			return template(
				'jumper/invalid',
				{
					error_code => 'HAS_SIMPLE_JUMPER',
					a_designation => $a_circuit_info->{full_designation},
					b_designation => $b_circuit_info->{full_designation},
				},
				{ layout => undef }
			);
		}

		# Both circuits must have some pins to link with the jumper
		unless($a_circuit_info->{pin_count} && $b_circuit_info->{pin_count}) {
			debug("cannot a jumper between these circuits - at least one of them has no pins");
			return template(
				'jumper/invalid',
				{
					error_code => 'NO PINS',
					a_designation => $a_circuit_info->{full_designation},
					b_designation => $b_circuit_info->{full_designation},
				},
				{ layout => undef }
			);
		}

		# Cannot offer simple jumper connection if:
		#   - there any other jumpers linking starting point and destination
		#   - starting and destination circuits are identical
		#   - starting and destination pin counts differ
		if(
			$connections->{complex}->{connection_count} ||
			$a_circuit_info->{id} == $b_circuit_info->{id} ||
			$a_circuit_info->{pin_count} != $b_circuit_info->{pin_count}
		) {	
			debug("cannot offer simple jumper - forward to custom jumper selection");
		}
		else {
			debug("offering choice of simple or custom jumper connection");
			my $a_pins = circuit_pins($a_circuit_info->{id});
			my $b_pins = circuit_pins($b_circuit_info->{id});
			my $max_pin_count = max(scalar(@{$a_pins}), scalar(@{$b_pins}));

			template(
				'jumper/choose_connection',
				{
					a_circuit => $a_circuit_info,
					b_circuit => $b_circuit_info,
					a_pins => $a_pins,
					b_pins => $b_pins,
					max_pin_index => ($max_pin_count - 1),
					replacing_jumper_id => param("replacing_jumper_id"),
					colours => get_colours()
				},
				{ layout => undef }
			);
		}
	};


	post '/wire_choice' => require_login sub {

		debug("wire_choice");
		debug( request->body);

		# Use the specified wire_count to determine which jumper
		# templates to present.
		my $wire_count = param("wire_count");
		$wire_count && $wire_count =~ m/^\d+$/ or do {
			error "wire_count is missing or not an integer";
			send_error('wire_count parameter is missing or not an integer.' => 400);
		};

		my $jumper_templates = get_jumper_templates($wire_count);

		template(
			'jumper/choose_wire',
			{
				jumper_templates => $jumper_templates,
				a_designation => param("a_designation"),
				b_designation => param("b_designation"),
			},
			{ layout => undef }
		);
	}

};




prefix '/api/jumper' => sub {

	del '/:jumper_id' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		my $id = param('jumper_id');
		jumper_id_valid_for_account($id) or do {
			send_error('forbidden' => 403);
		};

		delete_jumper($id);

		database->commit;

		return to_json {
			deleted => 1,
			jumper_id => $id,
		};
	};


	post '/add_simple_jumper' => sub {

		user_has_role('edit') or do {
			send_error('forbidden' => 403);
		};

		debug "add_simple_jumper()";
		debug request->body;

		# a_circuit_id is the starting point for this jumper - required parameter
		unless(defined param("a_circuit_id")) {
			send_error('Missing a_circuit_id parameter.' => 400);
		}
		unless(circuit_id_valid_for_account(param("a_circuit_id"))) {
			send_error('Bad a_circuit_id. Forbidden' => 403);
		}

		# b_circuit_id is the ending point for this jumper - required parameter
		unless(defined param("b_circuit_id")) {
			send_error('Missing b_circuit_id parameter.' => 400);
		}
		unless(circuit_id_valid_for_account(param("b_circuit_id"))) {
			send_error('Bad b_circuit_id. Forbidden' => 403);
		}

		# jumper_template_id to be used for this jumper - required parameter
		unless(defined param("jumper_template_id")) {
			send_error('Missing jumper_template_id parameter.' => 400);
		}
		unless(jumper_template_id_valid_for_account(param("jumper_template_id"))) {
			send_error('Bad jumper_template_id. Forbidden' => 403);
		}

		# replacing_jumper_id will be removed before inserting the new jumper - optional parameter
		if(param("replacing_jumper_id")) {
			jumper_id_valid_for_account(param("replacing_jumper_id")) or do {
				send_error('Bad replacing_jumper_id parameter. Forbidden' => 403);
			};
			delete_jumper(param("replacing_jumper_id"));
		}

		my $new_jumper_id = add_simple_jumper(
			param("a_circuit_id"),
			param("b_circuit_id"),
			param("jumper_template_id"),
		) or do {
			database->rollback;
			debug("add_simple_jumper didn't return a new jumper_id");
			send_error("failed to add jumper");
		};

		database->commit;

		return to_json {
			b_circuit_info => circuit_info(param("b_circuit_id")),
			jumper_id => $new_jumper_id,
		};
	};

};


sub jumper_id_valid_for_account {

	my $jumper_id = shift;
	my $account_id = shift || session('account')->{id};

	$jumper_id && $jumper_id =~ m/^\d+$/ or do {
		error "jumper_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM jumper_wire
		JOIN connection ON (connection.jumper_wire_id = jumper_wire.id)
		JOIN pin ON (pin.id = connection.pin_id)
		JOIN circuit ON (circuit.id = pin.circuit_id)
		JOIN block ON (block.id = circuit.block_id)
		JOIN vertical ON (vertical.id = block.vertical_id)
		JOIN frame ON (frame.id = vertical.frame_id) 
		WHERE jumper_wire.jumper_id = ?
		AND frame.account_id = ?
		LIMIT 1
	");

	$q->execute(
		$jumper_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub jumper_template_id_valid_for_account {

	my $id = shift;
	my $account_id = shift || session('account')->{id};

	$id && $id =~ m/^\d+$/ or do {
		error "jumper_template_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM jumper_template
		WHERE id = ?
		AND account_id = ?
	");

	return $q->execute(
		$id,
		$account_id,
	);
}


sub jumper_wire_connections {

	my $jumper_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM jumper_wire_connections
		WHERE jumper_id = ?
	");
	$q->execute($jumper_id);

	return $q->fetchall_arrayref({});
}


sub describe_jumper_connections {

	my $connections = shift;

	$connections or return "[no connections]";

	if($connections->[0]->{is_simple_jumper}) {
		my @designations = @{$connections->[0]->{full_circuit_designations}};
		return join('->', @designations);
	}
	else {
		my @wire_descriptions;
		foreach my $wire(@{$connections}) {
			push(
				@wire_descriptions,
				join('->', @{$wire->{full_pin_designations}})
			);
		}
		return join(', ', @wire_descriptions);
	}
}



sub get_connection_count {

	my $a_circuit_id = shift;
	my $b_circuit_id = shift;
	my $exclude_jumper_id = shift || 0;

	my $q = database->prepare("
		SELECT 
			CASE WHEN is_simple_jumper IS TRUE THEN 'simple' ELSE 'complex' END AS jumper_type,
			COUNT(*) as connection_count 
		FROM jumper_circuits
		WHERE a_circuit_id = ?
		AND b_circuit_id = ?
		AND jumper_id != ?
		GROUP BY jumper_type
	");
	$q->execute(
		$a_circuit_id,
		$b_circuit_id,
		$exclude_jumper_id,
	);
	my $connection_count = $q->fetchall_hashref("jumper_type");

	debug(sprintf(
		"circuits %s and %s are connected by %d simple jumpers and %d custom jumpers",
		$a_circuit_id,
		$b_circuit_id,
		$connection_count->{simple}->{connection_count}  || 0,
		$connection_count->{complex}->{connection_count} || 0,
	));

	return $connection_count;
}



sub delete_jumper {

	my $id = shift;
	debug "deleting jumper_id $id";

	my $connections = jumper_wire_connections($id);

	# Remove jumper and it's connections
	my $q = database->prepare(
		"SELECT delete_jumper(?)"
	);
	$q->execute(
		$id,
	) or do {
		database->rollback;
		send_error('error deleting jumper' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'jumper removed %s',
		describe_jumper_connections($connections)
	);

	# Technically jumpers could span an unlimited number of blocks
	# and circuits, so we only record activity at the frame level
	$al->record({
		function     => 'kronekeeper::Jumper::delete_jumper',
		frame_id     => $connections->[0]->{frame_id},
		note         => $note,
	});
}



sub prettify_designation {

	my $d = shift;

	# Strip any whitespace
	$d =~ s/\s//g;

	# Return as uppercase
	return uc($d);
}



sub get_jumper_templates {

	my $wire_count = shift;
	my $account_id = session('account')->{id};

	# Get the templates
	my $q = database->prepare("
		SELECT *
		FROM jumper_template
		WHERE jumper_template_wire_count(id) = ?
		AND account_id = ?
	");
	$q->execute($wire_count, $account_id);
	my $templates = $q->fetchall_arrayref({});

	# Add the wires for each template
	$q = database->prepare("
		SELECT
			jumper_template_wire.position AS position,
			colour.id AS colour_id,
			colour.name AS colour_name,
			colour.short_name AS colour_short_name,
			CONCAT('#', ENCODE(colour.html_code, 'hex')) AS html_colour,
			CONCAT('#', ENCODE(colour.contrasting_html_code, 'hex')) AS contrasting_html_colour
		FROM jumper_template_wire
		JOIN colour ON (colour.id = jumper_template_wire.colour_id)
		WHERE jumper_template_id = ?
		ORDER BY position ASC
	");

	foreach my $template(@{$templates}) {
		$q->execute($template->{id});
		$template->{wires} = $q->fetchall_arrayref({});
	}

	return $templates;
}


sub get_colours {

	# Get possible wire colours
	my $q = database->prepare("
		SELECT
			id,
			name,
			short_name,
			CONCAT('#', ENCODE(colour.html_code, 'hex')) AS html_colour,
			CONCAT('#', ENCODE(colour.contrasting_html_code, 'hex')) AS contrasting_html_colour
		FROM colour
		ORDER BY name
	");
	$q->execute();
	return $q->fetchall_arrayref({});
}


sub get_jumper_template_colour_names {

	my $jumper_template_id = shift;
	my $q = database->prepare("
		SELECT colour.name AS colour_name
		FROM jumper_template_wire
		JOIN colour ON (colour.id = jumper_template_wire.colour_id)
		WHERE jumper_template_wire.jumper_template_id = ?
		ORDER BY jumper_template_wire.position ASC
	");
	$q->execute($jumper_template_id);
	
	my @colour_names = map(
		$_->{colour_name},
		@{ $q->fetchall_arrayref({}) }
	);

	use Data::Dumper;
	debug Dumper \@colour_names;

	return \@colour_names;
}


sub add_simple_jumper {

	my $a_circuit_id = shift;
	my $b_circuit_id = shift;
	my $jumper_template_id = shift;

	debug(sprintf(
		"inserting jumper between circuits %s and %s with jumper_template %s",
		$a_circuit_id,
		$b_circuit_id,
		$jumper_template_id,
	));

	my $q = database->prepare("SELECT add_simple_jumper(?,?,?) AS jumper_id");
	$q->execute(
		$a_circuit_id,
		$b_circuit_id,
		$jumper_template_id,
	) or do {
		database->rollback;
		send_error("failed to add simple jumper");
	};

	my $result = $q->fetchrow_hashref;


	# Update activity log
	my $a_circuit_info = circuit_info($a_circuit_id);
	my $b_circuit_info = circuit_info($b_circuit_id);
	my $jumper_wire_colours = get_jumper_template_colour_names($jumper_template_id);

	my $note = sprintf(
		"standard jumper added %s->%s [%s]",
		$a_circuit_info->{full_designation},
		$b_circuit_info->{full_designation},
		join('/', @{$jumper_wire_colours}),
	);

	$al->record({
		function     => 'kronekeeper::Jumper::add_simple_jumper',
		frame_id     => $a_circuit_info->{frame_id},
		note         => $note,
	});


	return $result->{jumper_id};
}



1;
