/*
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
*/



/* Initialises a regular, rectangular frame to specified dimensions,
 * creating the frame record and inserting the required number of
 * empty block positions.
 * 
 * Block designations are created, by default running
 * left-to-right and bottom-to-top. The ordering of these designations
 * can be reversed by setting the p_reverse_vertical_designations and
 * p_reverse_block_designations parameters to TRUE.
 * 
 * Returns the id of the newly created frame.
 */
CREATE OR REPLACE FUNCTION create_regular_frame(
	p_account_id INTEGER,
	p_name TEXT,
	p_vertical_count INTEGER,
	p_row_count INTEGER,
	p_reverse_vertical_designations BOOLEAN,
	p_reverse_row_designations BOOLEAN
)
RETURNS INTEGER AS $$
DECLARE frame_id INTEGER;
DECLARE vertical_id INTEGER;
DECLARE vertical_designation TEXT;
DECLARE block_designation TEXT;
DECLARE maximum_size INTEGER := 500;
DECLARE designation_position INTEGER;
BEGIN
	
	/* Validation */
	CASE
		WHEN p_vertical_count IS NULL THEN
			RAISE EXCEPTION 'number of verticals cannot be NULL';
		WHEN p_vertical_count < 1 THEN
			RAISE EXCEPTION 'number of verticals cannot be less than 1';
		WHEN p_vertical_count > maximum_size THEN
			RAISE EXCEPTION 'number of verticals cannot be more than %', maximum_size;

		WHEN p_row_count IS NULL THEN
			RAISE EXCEPTION 'number of blocks in a vertical cannot be NULL';
		WHEN p_row_count < 1 THEN
			RAISE EXCEPTION 'number of blocks in a vertical cannot be less than 1';
		WHEN p_row_count > maximum_size THEN
			RAISE EXCEPTION 'number of blocks in a vertical cannot be more than %', maximum_size;

		ELSE -- validation OK
	END CASE;
		
	/* Create the frame */
	INSERT INTO frame(account_id, name)
	VALUES(p_account_id, p_name)
	RETURNING id INTO frame_id;

	RAISE DEBUG 'Inserted new frame with id:%', frame_id;

	/* Initialise the columns with empty blocks */
	FOR vertical_position IN 1..p_vertical_count LOOP

		/* Reversing vertical designations? */
		IF p_reverse_vertical_designations THEN
			designation_position := invert_position_index(vertical_position, p_vertical_count);
		ELSE
			designation_position := vertical_position;
		END IF;

		INSERT INTO vertical(frame_id, position, designation)
		VALUES(
			frame_id,
			vertical_position,
			regular_vertical_designation_from_position(designation_position)
		)
		RETURNING id, designation INTO vertical_id, vertical_designation;
		RAISE DEBUG 'Inserted vertical with designation %', vertical_designation;

		FOR block_position IN 1..p_row_count LOOP

			/* Reversing row designations? */
			IF p_reverse_row_designations THEN
				designation_position := invert_position_index(block_position, p_row_count);
			ELSE
				designation_position := block_position;
			END IF;

			INSERT INTO block(vertical_id, position, designation)
			VALUES(
				vertical_id,
				block_position,
				regular_block_designation_from_position(designation_position, p_row_count)
			)
			RETURNING designation INTO block_designation;
			RAISE NOTICE 'Inserted empty block with designation %', CONCAT(vertical_designation, block_designation);
		END LOOP;
	END LOOP;

	RETURN frame_id;
END
$$ LANGUAGE plpgsql;


