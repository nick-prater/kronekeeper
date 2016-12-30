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
use Array::Utils qw(array_minus);

my $al = kronekeeper::Activity_Log->new();


prefix '/user' => sub {

	get '/' => require_login sub {

		user_has_role('manage_users') or do {
			send_error('forbidden' => 403);
		};

		my $q = database->prepare("
			SELECT * FROM user_info
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

		template('user/password', {});
	};

	get '/:user_id' => require_login sub {

		my $user_id = param('user_id');
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
		use Data::Dumper;
		debug Dumper $template_data;
		template('user', $template_data);
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

		my $user_details = get_user_details($email);
		$al->record({
			function     => '/api/user/password',
			note         => sprintf("changed password for user '%s'", param('email')),
			to_person_id => $user_details->{id},
		});

		database->commit;

		return to_json {
			success => 1,
		};
	};

	patch '/:user_id' => require_login sub {

		my $user_id = param('user_id');
		my $current_user = logged_in_user;

		# A user can change their own details, otherwise
		# must have the manage_users role
		unless(
			($user_id == $current_user->{id}) ||
			user_has_role('manage_users') 
		) {
			send_error('forbidden' => 403);
		}

		# Can only change users on one's own account
		unless(user_id_valid_for_account($user_id)) {
			error("user is invalid for this account");
			send_error("user is invalid for this account" => 403);
		}

		debug request->body;
		my $data = from_json(request->body);
		my $changes = {};
		my $user_info = user_info($user_id);

		foreach my $field(keys %{$data}) {
			my $value = $data->{$field};
			for($field) {
				m/^email$/ and do {
					update_email($user_info, $value);
					$changes->{email} = $value;
					$user_info->{email} = $value;
					last;
				};
				m/^name$/ and do {
					update_name($user_info, $value);
					$changes->{name} = $value;
					last;
				};
				m/^roles$/ and do {
					update_roles($user_info, $value);
					$changes->{roles} = $value;
					last;
				};
				m/^is_active$/ and do {
					if($value) {
						database->rollback;
						error("can't re-enable a user using this route");
						send_error("can't re-enable a user using this route", 400);
					}
					else {
						disable_user($user_info);
						$changes->{is_active} = $value;
					}
					last;
				};
				# else
				error "failed to update unrecognised user field '$field'";
			}
		};


		database->commit;

		content_type 'application/json';
		return to_json $changes;
	};

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


sub user_id_valid_for_account {

	my $user_id = shift;
	my $account_id = shift || session('account')->{id};

	$user_id && $user_id =~ m/^\d+$/ or do {
		error "user_id is not an integer";
		return undef;
	};
	$account_id && $account_id =~ m/^\d+$/ or do {
		error "account_id is not an integer";
		return undef;
	};

	my $q = database->prepare("
		SELECT 1
		FROM person
		WHERE id = ?
		AND account_id = ?
	");

	$q->execute(
		$user_id,
		$account_id,
	);

	return $q->fetchrow_hashref;
}


sub user_role_max_rank {
	my $user_id = shift;
	my $q = database->prepare("
		SELECT MAX(rank) AS max_rank
		FROM user_role
		JOIN role ON (role.id = user_role.role_id)
		WHERE user_role.user_id = ?
	");
	$q->execute($user_id);
	my $r = $q->fetchrow_hashref or return undef;

	return $r->{max_rank};
}


sub user_info {
	my $user_id = shift;
	my $q = database->prepare("
		SELECT *
		FROM user_info 
		WHERE id = ?
	");
	$q->execute($user_id);
	return $q->fetchrow_hashref;
}


sub roles {
	my $q = database->prepare("
		SELECT * FROM role
	");
	$q->execute;
	return $q->fetchall_hashref('role');
}


sub update_name {
	my $info = shift;
	my $name = shift;

	# Rename user
	my $q = database->prepare("
		UPDATE person
		SET name = ?
		WHERE id = ?
	");

	$q->execute(
		$name,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating user name' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'user renamed "%s" (was "%s")',
		$name,
		$info->{name} || '',
	);

	$al->record({
		function     => 'kronekeeper::User::update_name',
		note         => $note,
		to_person_id => $info->{id},
	});
}


sub update_email {
	my $info = shift;
	my $email = shift;

	# Validation
	if($email eq $info->{email}) {
		info("new e-mail matches existing e-mail - no update needed");
		return;
	}
	elsif(get_user_details($email)) {
		database->rollback;
		error("cannot change user e-mail as it conflicts with an existing user");
		send_error("New login conflicts with an existing user", 409);
	};

	my $q = database->prepare("
		UPDATE person
		SET email= ?
		WHERE id = ?
	");

	$q->execute(
		$email,
		$info->{id},
	) or do {
		database->rollback;
		send_error('error updating user name' => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'user email changed to "%s" (was "%s")',
		$email,
		$info->{email} || '',
	);

	$al->record({
		function     => 'kronekeeper::User::update_email',
		note         => $note,
		to_person_id => $info->{id},
	});
}


sub update_roles {

	my $info = shift;
	my $roles = shift;
	my $existing_roles = user_roles($info->{email});

	my @roles_to_remove = array_minus(
		@{$existing_roles},
		@{$roles}
	);
	debug("Need to remove roles: ", join(",", @roles_to_remove));
	foreach my $role(@roles_to_remove) {
		remove_role($role, $info);
	}


	my @roles_to_add = array_minus(
		@{$roles},
		@{$existing_roles}
	);
	debug("Need to add roles: ", join(",", @roles_to_add));
	foreach my $role(@roles_to_add) {
		add_role($role, $info);
	}
}



sub allowed_to_edit_role {

	my $role = shift;
	my $current_user = logged_in_user;
	my $current_user_max_rank = user_role_max_rank($current_user->{id});

	my $q = database->prepare("
		SELECT 1
		FROM role
		WHERE role.role = ?
		AND role.rank <= ?
	");
	$q->execute(
		$role,
		$current_user_max_rank,
	);

	return $q->fetchrow_hashref;
}



sub remove_role {

	my $role = shift;
	my $info = shift;

	debug("removing role $role for user $info->{email}");

	allowed_to_edit_role($role) or do {
		database->rollback;
		error("error: insufficient permissions to remove role");
		send_error("error removing role $role" => 403);
	};

	my $q = database->prepare("
		DELETE FROM user_role
		USING role
		WHERE role.id = user_role.role_id
		AND user_role.user_id = ?
		AND role.role = ?
	");
	$q->execute($info->{id}, $role) or do {
		database->rollback;
		error("error removing role");
		send_error("error removing role $role" => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'Removed role %s for user %s',
		$role,
		$info->{email} || '',
	);
	$al->record({
		function     => 'kronekeeper::User::remove_role',
		note         => $note,
		to_person_id => $info->{id},
	});
}


sub add_role {

	my $role = shift;
	my $info = shift;

	debug("adding role $role for user $info->{email}");

	allowed_to_edit_role($role) or do {
		database->rollback;
		error("error: insufficient permissions to add role");
		send_error("error adding role $role" => 403);
	};

	my $q = database->prepare("
		INSERT INTO user_role (user_id, role_id)
		SELECT ?, id
		FROM role
		WHERE role.role = ?
	");
	$q->execute($info->{id}, $role) or do {
		database->rollback;
		error("error adding role");
		send_error("error adding role $role" => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'Added role %s for user %s',
		$role,
		$info->{email} || '',
	);
	$al->record({
		function     => 'kronekeeper::User::add_role',
		note         => $note,
		to_person_id => $info->{id},
	});
}


sub disable_user {

	# We disable users by setting an empty password in the database.
	# This is considered invalid - all valid passwords are stored as hashes
	my $info = shift;
	debug("disabling login for user $info->{email}");

	my $q = database->prepare("
		UPDATE person
		SET password = ''
		WHERE id = ?
	");
	$q->execute($info->{id}) or do {
		database->rollback;
		error("error disabling user");
		send_error("error disabling user" => 500);
	};

	# Update Activity Log
	my $note = sprintf(
		'Disabled login for user %s',
		$info->{email} || '',
	);
	$al->record({
		function     => 'kronekeeper::User::disable_user',
		note         => $note,
		to_person_id => $info->{id},
	});
}


1;
