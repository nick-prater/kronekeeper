package kronekeeper::Account;

=head1 LICENCE

This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2019 NP Broadcast Limited

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
use Array::Utils qw(array_minus);
use Exporter qw(import);
our $VERSION = '0.01';
our @EXPORT_OK = qw();


my $al = kronekeeper::Activity_Log->new();


prefix '/account' => sub {

	get '/' => require_login sub {

		user_has_role('manage_accounts') or do {
			send_error('forbidden' => 403);
		};

		template('accounts', {
			accounts => accounts(),
		});
	};

	get '/new' => require_login sub {

		my $current_user = logged_in_user;

		unless(user_has_role('manage_accounts')) {
			error("user does not have manage_accounts role");
			send_error('forbidden' => 403);
		}

		my $account = {
			id => undef,
			name => '',
			roles => [],
		};

		my $template_data = {
			role_max_rank => user_role_max_rank($current_user->{id}),
			#user => $user,
			roles => roles(),
		};
		template('user', $template_data);
	};

	get '/:account_id' => require_login sub {

		my $account_id = param('account_id');

		# Viewing and editing account details is an admin task
		unless(user_has_role('manage_accounts')) {
			error("user does not have manage_accounts role");
			send_error('forbidden' => 403);
		}

		my $account = account_info($account_id);

		my $template_data = {
			account => $account,
		};
		template('account', $template_data);
	};
};


prefix '/api/account' => sub {

	patch '/:account_id' => require_login sub {

		# Changing account details is an admin task
		unless(user_has_role('manage_accounts')) {
			error("user does not have manage_accounts role");
			send_error('forbidden' => 403);
		}

		my $account_id = param('account_id');
		my $info = account_info($account_id);

		debug request->body;
		my $data = from_json(request->body);
		my $changes = {};

		foreach my $field(keys %{$data}) {
			my $value = $data->{$field};
			for($field) {
				m/^name$/ and do {
					update_name($info, $value);
					$changes->{name} = $value;
					last;
				};
				m/^max_frame_(count|width|height)$/ and do {
					update_frame_limit($info, $field, $value);
					$changes->{$field} = $value;
					last;
				};
				# else
				error "failed to update unrecognised account field '$field'";
			}
		};

		database->commit;

		content_type 'application/json';
		return to_json $changes;
	};


};


sub accounts {
	my $account_id = shift || session('account')->{id};
	my $q = database->prepare("
		SELECT * FROM account
		ORDER BY name ASC
	");
	$q->execute();
	return $q->fetchall_arrayref({})
}


sub account_info {
	my $account_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM account
		WHERE id = ?
	");
	$q->execute($account_id);
	return $q->fetchrow_hashref;
}


sub update_name {
	my $info = shift;
	my $name = shift;

	# Rename user
	my $q = database->prepare('
		UPDATE account
		SET name = ?
		WHERE id = ?
	');

	$q->execute(
		$name,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating account name' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'account renamed "%s" (was "%s")',
		$name,
		$info->{name} || '',
	);

	$al->record({
		function     => 'kronekeeper::Account::update_name',
                account_id   => $info->{id},
		note         => $note,
	});
}


sub update_frame_limit {

	my $info = shift;
	my $field = shift;
	my $value = shift;

	# Field name is used to build query - constrain to valid field names
	$field =~ m/^max_frame_(count|width|height)$/ or do {
		send_error("invalid field $field" => 400);
	};

	# An empty value is recorded as NULL - no limit
	if($value eq '') {
		$value = undef;
	}

	my $q = database->prepare("
		UPDATE account
		SET $field = ?
		WHERE id = ?
	");

	$q->execute(
		$value,
		$info->{id},
	);

	# Update Activity Log
	my $note = sprintf(
		'account limit %s changed to "%s" (was "%s")',
		$field,
		$value,
		$info->{$field} || '',
	);

	$al->record({
		function     => 'kronekeeper::Account::update_frame_limit',
                account_id   => $info->{id},
		note         => $note,
	});
}


1;
