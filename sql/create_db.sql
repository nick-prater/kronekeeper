/*
This file is part of Kronekeeper, a web based application for 
recording and managing wiring frame records.

Copyright (C) 2016-2017 NP Broadcast Limited

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
*/


CREATE DATABASE kronekeeper;

/*--------------------------------------------------------------------------*/
/* HOUSEKEEPING */
/*--------------------------------------------------------------------------*/

CREATE TABLE account(
        id SERIAL NOT NULL PRIMARY KEY,
        name TEXT NOT NULL
);

CREATE TABLE person(
	id SERIAL NOT NULL PRIMARY KEY,
	account_id INTEGER NOT NULL REFERENCES account(id),
	email TEXT NOT NULL,
	name TEXT NOT NULL,
	password TEXT NOT NULL
);
CREATE UNIQUE INDEX person_email_idx ON person(email);

CREATE TABLE role(
	id SERIAL NOT NULL PRIMARY KEY,
	role TEXT NOT NULL,
	rank INTEGER NOT NULL DEFAULT 100
);
CREATE UNIQUE INDEX role_idx ON role(role);

CREATE TABLE user_role(
	user_id INTEGER NOT NULL REFERENCES person(id),
	role_id INTEGER NOT NULL REFERENCES role(id)
);
CREATE UNIQUE INDEX user_role_idx ON user_role(user_id, role_id);

CREATE TABLE activity_log(
	id SERIAL NOT NULL PRIMARY KEY,
	log_timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),	
	by_person_id INTEGER REFERENCES person(id),
	account_id INTEGER REFERENCES account(id),
	frame_id INTEGER REFERENCES frame(id),
	function TEXT,
	note TEXT,
	block_id_a INTEGER REFERENCES block(id),
	circuit_id_a INTEGER REFERENCES circuit(id),
	to_person_id INTEGER REFERENCES person(id),
	comment TEXT,
	completed_by_person_id INTEGER REFERENCES person(id)
);

/* Initialise Roles */
INSERT INTO role(role) VALUES ('edit');
INSERT INTO role(role) VALUES ('view_activity_log');
INSERT INTO role(role) VALUES ('import');
INSERT INTO role(role, rank) VALUES ('manage_users', 1000);



/*--------------------------------------------------------------------------*/
/* PERMANENT WIRING */
/*--------------------------------------------------------------------------*/

CREATE TABLE frame(
	id SERIAL NOT NULL PRIMARY KEY,
	account_id INTEGER NOT NULL REFERENCES account(id),
	name TEXT NOT NULL DEFAULT '',
	is_template BOOLEAN NOT NULL DEFAULT FALSE,
	is_deleted BOOLEAN NOT NULL DEFAULT FALSE
);

	
CREATE TABLE vertical(
	id SERIAL NOT NULL PRIMARY KEY,
	frame_id INTEGER NOT NULL REFERENCES frame(id),
	position INTEGER NOT NULL CHECK(position > 0),
	designation TEXT
);
CREATE UNIQUE INDEX vertical_frame_position_idx ON vertical(frame_id, position);
CREATE UNIQUE INDEX vertical_frame_designation_idx ON vertical(designation, frame_id);

/* Transform these indexes into constraints so we can defer them during updates */
ALTER TABLE vertical
ADD CONSTRAINT vertical_unique_frame_position
UNIQUE USING INDEX vertical_frame_position_idx
DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE vertical
ADD CONSTRAINT vertical_unique_frame_designation
UNIQUE USING INDEX vertical_frame_designation_idx
DEFERRABLE INITIALLY IMMEDIATE;


CREATE TABLE block_type(
	id SERIAL NOT NULL PRIMARY KEY,
	account_id INTEGER NOT NULL REFERENCES account(id),
	name TEXT NOT NULL,
	colour_html_code BYTEA NOT NULL,
	circuit_count INTEGER NOT NULL,
	circuit_pin_count INTEGER NOT NULL
);


CREATE TABLE block(
	id SERIAL NOT NULL PRIMARY KEY,
	block_type_id REFERENCES block_type(id),
	vertical_id INTEGER NOT NULL REFERENCES vertical(id),
	position INTEGER NOT NULL CHECK(position > 0),
	designation TEXT,
	name TEXT,
	block_type_id INTEGER REFERENCES block_type(id),
	colour_html_code BYTEA
);
CREATE UNIQUE INDEX block_vertical_position_idx ON block(vertical_id, position);
CREATE UNIQUE INDEX block_designation_vertical_idx ON block(designation, vertical_id);

/* Transform these indexes into constraints so we can defer them during updates */
ALTER TABLE block
ADD CONSTRAINT block_unique_vertical_position
UNIQUE USING INDEX block_vertical_position_idx
DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE block
ADD CONSTRAINT block_unique_vertical_designation
UNIQUE USING INDEX block_designation_vertical_idx
DEFERRABLE INITIALLY IMMEDIATE;


CREATE TABLE circuit(
	id SERIAL NOT NULL PRIMARY KEY,
	block_id INTEGER NOT NULL REFERENCES block(id),
	position INTEGER NOT NULL CHECK(position > 0),
	designation TEXT,
	name TEXT,
	cable_reference TEXT,
	connection TEXT,
	note TEXT
);
CREATE UNIQUE INDEX circuit_block_position_idx ON circuit(block_id, position);
CREATE UNIQUE INDEX circuit_designation_block_idx ON circuit(designation, block_id);

CREATE TABLE pin(
	id SERIAL NOT NULL PRIMARY KEY,
	circuit_id INTEGER NOT NULL REFERENCES circuit(id),
	position INTEGER NOT NULL CHECK(position > 0),
	designation TEXT,
	name TEXT,
	wire_reference TEXT
);
CREATE UNIQUE INDEX pin_circuit_position_idx ON pin(circuit_id, position);
CREATE UNIQUE INDEX pin_designation_circuit_idx ON pin(designation, circuit_id);


/*--------------------------------------------------------------------------*/
/* JUMPER TEMPLATES */
/*--------------------------------------------------------------------------*/

CREATE TABLE colour(
	id SERIAL NOT NULL PRIMARY KEY,
	html_code BYTEA NOT NULL,
	name TEXT NOT NULL,
	short_name TEXT NOT NULL,
	contrasting_html_code BYTEA NOT NULL DEFAULT E'\\x000000'
);
CREATE UNIQUE INDEX colour_name_idx ON colour(name);
CREATE UNIQUE INDEX colour_short_name_idx ON colour(short_name);

/* Insert basic cable colours */
INSERT INTO colour(name, short_name, html_code, contrasting_html_code) VALUES 
	('blue',  'blu', E'\\x0000FF', E'\\xffffff'),
	('orange', 'or', E'\\xFFA500', E'\\xffffff'),
	('green',  'gn', E'\\x008000', E'\\xffffff'),
	('brown',  'bn', E'\\x8b4513', E'\\xffffff'),
	('slate',  's',  E'\\x808080', E'\\xffffff'),
	('white',  'w',  E'\\xffffff', E'\\x000000'),
	('red',    'r',  E'\\xff0000', E'\\xffffff'),
	('black', 'blk', E'\\x000000', E'\\xffffff'),
	('yellow', 'y',  E'\\xffd700', E'\\x000000'),
	('violet', 'v',  E'\\x800080', E'\\xffffff');

CREATE TABLE jumper_template(
	id SERIAL NOT NULL PRIMARY KEY,
	name TEXT,
	designation TEXT,
	account_id INTEGER NOT NULL REFERENCES account(id)
);
CREATE UNIQUE INDEX jumper_template_designation_idx ON jumper_template(designation);

CREATE TABLE jumper_template_wire(
	id SERIAL NOT NULL PRIMARY KEY,
	jumper_template_id INTEGER NOT NULL REFERENCES jumper_template(id),
	position INTEGER NOT NULL CHECK(position > 0),
	colour_id INTEGER NOT NULL REFERENCES colour(id)
);


/* Creates a new jumper template, returning the jumper's id.
 * arguments:
 *  template_name   e.g. 'Analogue Audio - Left'
 *  designation     e.g. 'L'
 *  colour array    e.g. {'blu', 'r'}
 * A corresponding jumper_template_wire record will be created for
 * however many short color names are provided
 */
CREATE OR REPLACE FUNCTION create_jumper_template(
	p_account_id INTEGER,
	p_template_name TEXT,
	p_template_designation TEXT,
	p_wire_colours TEXT[]
)
RETURNS INTEGER AS $$
DECLARE p_jumper_template_id INTEGER;
DECLARE p_position INTEGER := 1;
DECLARE p_wire_colour_name TEXT;
DECLARE p_wire_colour_id INTEGER;
BEGIN

	INSERT INTO jumper_template(name, designation, account_id)
	VALUES(p_template_name, p_template_designation, p_account_id)
	RETURNING id INTO p_jumper_template_id;

	FOREACH p_wire_colour_name IN ARRAY p_wire_colours LOOP

		RAISE NOTICE 'wire % : colour %', p_position, p_wire_colour_name;

		SELECT id INTO p_wire_colour_id
		FROM colour
		WHERE name = p_wire_colour_name
		OR short_name = p_wire_colour_name;

		IF p_wire_colour_id IS NULL THEN
			RAISE EXCEPTION 'unable to find colour with name or short_name %', p_wire_colour_name;
		END IF;

		INSERT INTO jumper_template_wire (jumper_template_id, position, colour_id)
		VALUES (p_jumper_template_id, p_position, p_wire_colour_id);

		p_position := p_position + 1;

	END LOOP;

	RETURN p_jumper_template_id;
END
$$ LANGUAGE plpgsql;

/* Insert Basic Jumper Templates 
 * This needs re-work now that we've made the templates per-account
SELECT create_jumper_template(2, 'Analogue Right', 'R',     ARRAY['blu','y']);
SELECT create_jumper_template(2, 'Analogue Left',  'L',     ARRAY['blu','red']);
SELECT create_jumper_template(2, 'Analogue Mono',  'M',     ARRAY['red','white']);
SELECT create_jumper_template(2, 'DC',             'DC',    ARRAY['green','yellow']);
SELECT create_jumper_template(2, 'AES/EBU',        'AES',   ARRAY['blue','white']);
SELECT create_jumper_template(2, 'Communications', 'COMMS', ARRAY['green','red']);
SELECT create_jumper_template(2, 'ABS',            'ABS',   ARRAY['black','red','green']);
 */


/*--------------------------------------------------------------------------*/
/* JUMPERS */
/*--------------------------------------------------------------------------*/

CREATE TABLE jumper(
	id SERIAL NOT NULL PRIMARY KEY
);

CREATE TABLE jumper_wire(
	id SERIAL NOT NULL PRIMARY KEY,
	jumper_id INTEGER NOT NULL REFERENCES jumper(id),
	colour_id INTEGER NOT NULL REFERENCES colour(id)
);

CREATE TABLE connection(
	id SERIAL NOT NULL PRIMARY KEY,
	jumper_wire_id INTEGER NOT NULL REFERENCES jumper_wire(id),
	pin_id INTEGER NOT NULL REFERENCES pin(id)
);
CREATE UNIQUE INDEX connection_jumper_wire_pin_idx ON connection(jumper_wire_id, pin_id);
CREATE INDEX connection_pin_idx ON connection(pin_id);
/* TODO: add constraint/trigger so a jumper wire has exactly two connections */




/*--------------------------------------------------------------------------*/
/* KRIS IMPORT */
/*--------------------------------------------------------------------------*/

/* The tables in this schema are only required to enable import of data from KRIS data files */
CREATE SCHEMA kris;

CREATE TABLE kris.jumper_type(
	id SERIAL NOT NULL PRIMARY KEY,
	account_id INTEGER NOT NULL REFERENCES public.account(id),
	kris_wiretype_id INTEGER NOT NULL,
	name TEXT NOT NULL,
	a_wire_colour_code BYTEA NOT NULL,
	b_wire_colour_code BYTEA NOT NULL,
	jumper_template_id INTEGER REFERENCES public.jumper_template(id)
);

CREATE UNIQUE INDEX kris_jumper_type_account_wiretype_idx ON kris.jumper_type(account_id, kris_wiretype_id);



/*--------------------------------------------------------------------------*/
/* PERMISSIONS */
/*--------------------------------------------------------------------------*/

GRANT USAGE ON SCHEMA kris TO kkdancer;
GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES IN SCHEMA public TO kkdancer;
GRANT SELECT, INSERT, DELETE, UPDATE ON ALL TABLES IN SCHEMA kris TO kkdancer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO kkdancer;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA kris TO kkdancer;


/* Adding an account */
-- insert initial block types
-- insert initial jumper templates
-- INSERT INTO block_type(account_id, name, colour_html_code, circuit_count, circuit_pin_count) VALUES (2, '237A', E'\\xfffacd', 10, 2);
-- INSERT INTO block_type(account_id, name, colour_html_code, circuit_count, circuit_pin_count) VALUES (2, '237B', E'\\xd6dddd', 10, 2);
-- INSERT INTO block_type(account_id, name, colour_html_code, circuit_count, circuit_pin_count) VALUES (2, 'EARTH', E'\\xffcccc', 10, 2);
-- INSERT INTO block_type(account_id, name, colour_html_code, circuit_count, circuit_pin_count) VALUES (2, 'ABS', E'\\xd6dddd', 6, 3);





