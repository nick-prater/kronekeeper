package kronekeeper::AuthDB;

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
use base "Dancer2::Plugin::Auth::Extensible::Provider::Database";

our $VERSION = '0.1';


=head1 SUMMARY

A later version of Dancer2::Plugin::Auth::Extensible::Provider::Database 
provide methods for adding/altering users, but that's only available in
github at the time of writing and has dependencies on updating other
module versions which are only available in github...

Rather then play dependency hell, we subclass the existing Dancer2 module
and create our own methods to provide these functions. This makes
installation easier too. In time, once updated modules filter through
CPAN and distributions, we can remove this code and use the native
Dancer2 modules.

=cut



sub create_user {

	my ( $self, %options ) = @_;

	$options{username}   or die "no username specified";
	$options{account_id} or die "no account name specified";
	$options{name}       or die "no account name specified";

	my $settings = $self->realm_settings;
    	my $db = $self->realm_dsl->database($settings->{db_connection_name});

	my $q = $db->prepare("
		INSERT INTO person (account_id, email, name, password)
		VALUES (?,?,?,?)
	");

	$q->execute(
		$options{account_id},
		$options{username},
		$options{name},
		'',  # can't use null password, so use empty string, which disallows logins
	) or die "failed to insert new user record";

	my $user_id = $db->last_insert_id(undef, 'public', 'person', 'id');
	return $user_id;
}



sub set_user_password {

	my $self = shift;
	my $username = shift;
	my $password = shift;

	$username or die "no username specified";
	$password or die "no account name specified";

	my $settings = $self->realm_settings;
    	my $db = $self->realm_dsl->database($settings->{db_connection_name});
	my $encrypted_password = $self->encrypt_password($password);

	my $q = $db->prepare("
		UPDATE person
		SET password = ?
		WHERE email = ?
	");

	$q->execute(
		$encrypted_password,
		$username,
	) or die "failed to update password";

	return 1;
}




1;
