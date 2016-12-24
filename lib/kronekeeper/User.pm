package kronekeeper::User;

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

my $al = kronekeeper::Activity_Log->new();


prefix '/user' => sub {

	get '/' => require_login sub {

		user_has_role('manage_users') or do {
			send_error('forbidden' => 403);
		};

		my $q = database->prepare("
			SELECT * FROM person
			WHERE account_id = ?
			ORDER BY name ASC
		");
		$q->execute(
			session('account')->{id}
		);

		template('users', {
			users => $q->fetchall_arrayref({})
		});
	};

	get '/password' => require_login sub {



		template('user/password', {

		});
	};
};


prefix '/api/user' => sub {

	post '/add' => require_login sub {

		user_has_role('manage_users') or do {
			send_error('forbidden' => 403);
		};

		param('email') or send_error('missing email parameter' => 400);
		param('name') or send_error('missing name parameter' => 400);
		my $account_id = param('account_id') || session('account')->{id};

		if($account_id != param('account_id')) {
			error("cannot add user for another account");
			send_error("cannot add user for another account" => 403);
		}

		if(get_user_details(param('email'))) {
			error(sprintf("user %s already exists", param('email')));
			send_error('user already exists' => 400);
		}

		my $user_id = create_user(
			username   => param('email'),
			account_id => $account_id,
			name       => param('name'),
		) or do {
			database->rollback;
			send_error('error creating user' => 500);
		};

		$al->record({
			function   => '/api/user/add',
			account_id => param('account_id'),
			note       => sprintf("added new user '%s'", param('email'))
		});

		database->commit;

		return to_json {
			user_id => $user_id
		};
	};


	post '/password' => require_login sub {

		# We use the underlying Dancer2 libraries to update passwords as
		# these abstract their encryption/checking, rather than directly
		# manipulating the person database table.
		#
		# Dancer2::Plugin::Auth::Extensible keys by username (which is an
		# e-mail address in our case) rather than by numeric id, so we
		# expect an e-mail address to specify which user to update.
		# 
		# If no e-mail address is specified we default to changing the
		# password for the current logged-in user.
		#
		# Only users with the 'manage_users' role can change the password
		# of a user other than themselves and then only if the user being
		# changed belongs to the same account.
		#
		# To change one's own password, the current password must also
		# be provided.

		my $user = logged_in_user;
		my $email = param('email') || $user->{email};
		my $old_password = param('old_password');
		my $new_password = param('new_password');

		# Validation
		unless(defined $new_password) {
			# Required parameter
			error("missing new_password parameter");
			send_error('missing password parameter' => 400);
		}

		unless(user_email_valid_for_account($email)) {
			error("email is invalid for this account");
			send_error("email is invalid for this account" => 403);
		}

		if($email eq $user->{email}) {
			# Changing our own password - must provide current password
			defined $old_password or do {
				error("missing old_password parameter when changing own password");
				send_error("missing old_password parameter when changing own password" => 400);
			};
			authenticate_user($email, $old_password) or do {
				error("invalid old_password");
				send_error("invalid old_password" => 403);
			};
		}
		elsif(!user_has_role('manage_users')) {
			# Changing somebody else's password - must have manage_users role
			error("trying to update another user's password without manage_users role");
			send_error('forbidden' => 403);
		}

		# Update password
		user_password(
			username     => $email,
			new_password => $new_password,
		) or do {
			error("error changing password");
			send_error('error changing password' => 500);
		};

		$al->record({
			function => '/api/user/password',
			note     => sprintf("changed password for user '%s'", param('email'))
		});

		database->commit;

		return to_json {
			success => 1,
		};
	}

};



sub user_email_valid_for_account {

	my $email = shift;
	my $account_id = shift || session('account')->{id};

	$email or do {
		error "user email is empty or undefined";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM person
		WHERE email = ?
		AND account_id = ?
	");

	$q->execute(
		$email,
		$account_id,
	);

	return $q->fetchrow_hashref;
}




1;
