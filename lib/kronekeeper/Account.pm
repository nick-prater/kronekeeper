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

		my $user_id = param('account_id');
		my $current_user = logged_in_user;

		# A user can edit their own details, otherwise
		# must have the manage_users role
		unless(
			($user_id == $current_user->{id}) ||
			user_has_role('manage_users') 
		) {
			send_error('forbidden' => 403);
		}

		# Can only view details of users on one's own account
		unless(user_id_valid_for_account($user_id)) {
			error("user is invalid for this account");
			send_error("user is invalid for this account" => 403);
		}

		my $user = user_info($user_id);
		$user->{roles} = user_roles($user->{email});

		# Build hash of roles to help UI construction
		my $roles = roles();
		foreach my $role(@{$user->{roles}}) {
			$roles->{$role}->{assigned} = 1;
		}

		my $template_data = {
			role_max_rank => user_role_max_rank($current_user->{id}),
			user => $user,
			roles => $roles,
		};
		template('user', $template_data);
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


1;
